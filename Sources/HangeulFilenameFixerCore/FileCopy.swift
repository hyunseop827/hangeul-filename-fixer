// Plans and makes the NFC-named copy. The original is only ever read.
import Darwin

private let quarantineAttribute = "com.apple.quarantine"

public struct PlanInput: Sendable, Equatable {
	public var sourcePath: String
	public var outputDirectory: String
	/// Empty string keeps the original name.
	public var baseName: String

	public init(sourcePath: String, outputDirectory: String, baseName: String) {
		self.sourcePath = sourcePath
		self.outputDirectory = outputDirectory
		self.baseName = baseName
	}

	/// Equal only when every field is spelled the same, byte for byte. The synthesized `==` would compare the Strings
	/// by canonical equivalence and call an NFC and an NFD path the same input.
	public static func == (first: PlanInput, second: PlanInput) -> Bool {
		first.sourcePath.utf8.elementsEqual(second.sourcePath.utf8)
			&& first.outputDirectory.utf8.elementsEqual(second.outputDirectory.utf8)
			&& first.baseName.utf8.elementsEqual(second.baseName.utf8)
	}
}

public struct FileCopyPlan: Sendable {
	public let sourcePath: String
	/// The source file name as stored on disk (NFC or NFD), not as spelled in sourcePath.
	public let sourceName: String
	public let destinationPath: String
	public let destinationName: String
	/// True when " (n)" was added because the name was taken, e.g. by the original in the same folder.
	public let hasNumberSuffix: Bool

	public init(sourcePath: String, sourceName: String, destinationPath: String, destinationName: String, hasNumberSuffix: Bool) {
		self.sourcePath = sourcePath
		self.sourceName = sourceName
		self.destinationPath = destinationPath
		self.destinationName = destinationName
		self.hasNumberSuffix = hasNumberSuffix
	}
}

/// Returns nil when the source is not a regular file (folder, app bundle, missing path).
public func makePlan(_ input: PlanInput) -> FileCopyPlan? {
	makePlan(input, fileSystem: .real)
}

/// Copies the file under its NFC, Windows-safe name and checks the name the volume really stored.
/// Every failure is a `UserFacingError` with a Korean message; a copy that failed half-way is removed.
public func copyNormalizedFile(_ input: PlanInput) throws(UserFacingError) -> FileCopyPlan {
	try copyNormalizedFile(input, fileSystem: .real)
}

func makePlan(_ input: PlanInput, fileSystem: FileSystemAccess) -> FileCopyPlan? {
	guard let sourceStatus = try? status(atPath: input.sourcePath), isRegularFile(sourceStatus) else {
		return nil
	}

	// Paths from a drag, an open panel or a URL may arrive decomposed (NFD) even for NFC files, so ask the folder for
	// the real name.
	var sourceName = baseName(ofPath: input.sourcePath)
	if let storedName = try? storedFileName(atPath: input.sourcePath, identity: FileIdentity(sourceStatus), fileSystem: fileSystem) {
		sourceName = storedName
	}
	// (When the folder cannot be read, the spelling from the path is kept.)

	let (stem, fileExtension) = splitFileName(sourceName)
	let keepsOriginalName = input.baseName.javaScriptTrimmed().unicodeScalars.isEmpty
	let requestedStem = keepsOriginalName ? stem : customStem(input.baseName, extension: fileExtension)
	let firstCandidate = joinPath(input.outputDirectory, windowsSafeFileName(stem: requestedStem, extension: fileExtension))
	let destination = uniqueDestinationPath(firstCandidate, fileSystem: fileSystem)

	return FileCopyPlan(
		sourcePath: input.sourcePath,
		sourceName: sourceName,
		destinationPath: destination.path,
		destinationName: baseName(ofPath: destination.path),
		hasNumberSuffix: destination.hasNumberSuffix
	)
}

func copyNormalizedFile(_ input: PlanInput, fileSystem: FileSystemAccess) throws(UserFacingError) -> FileCopyPlan {
	do {
		return try copyAndVerify(input, fileSystem: fileSystem)
	} catch let error as UserFacingError {
		throw error
	} catch let error as SystemCallError {
		throw userFacingError(forErrno: error.code)
	} catch {
		// Nothing else is thrown in this module; kept so a new error type can never escape unworded.
		throw UserFacingError(message: localized(Message.copyFailed))
	}
}

private func copyAndVerify(_ input: PlanInput, fileSystem: FileSystemAccess) throws -> FileCopyPlan {
	guard let plan = makePlan(input, fileSystem: fileSystem) else {
		throw UserFacingError(message: notRegularFileMessage)
	}

	guard isReadable(atPath: plan.sourcePath) else {
		throw UserFacingError(message: localized(Message.sourceNotReadable))
	}

	// The original is opened for reading only, and nothing but read calls ever touch it.
	// No O_NONBLOCK, as in the Electron app (libuv opened the source with O_RDONLY alone). It would only matter when
	// another process swaps a FIFO in between the check above and this call: the open then waits for a writer, which
	// is accepted. With the flag, open(2) does "not wait for the … file to be ready" (its manual), and what that does
	// to a file that still has to be downloaded from iCloud could not be tried.
	let source = try openDescriptor(atPath: plan.sourcePath, flags: O_RDONLY | O_CLOEXEC)
	defer { close(source) }

	// Checked again on the open descriptor: open(2) also succeeds on a folder that took the file's place, and
	// fcopyfile would "copy" it as an empty file.
	let sourceStatus = try status(ofDescriptor: source)
	guard isRegularFile(sourceStatus) else {
		throw UserFacingError(message: notRegularFileMessage)
	}

	// O_EXCL: never overwrite a file that appeared after the name was chosen. It also refuses a dangling symlink and
	// the same name in the other normalization. Created without any permission bit, so the process's umask has
	// nothing to take away; the mode is set right below.
	let destination = try openDescriptor(atPath: plan.destinationPath, flags: O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode: 0)
	var destinationIsOpen = true
	defer {
		if destinationIsOpen {
			close(destination)
		}
	}

	do {
		// The copy stays private (0600) until it is complete. Set with fchmod and not by open(2): a mode given to
		// open is filtered by the umask, and without the owner's write bit the quarantine flag cannot be written.
		try systemCall { fchmod(destination, 0o600) }
		try copyData(from: source, to: destination)
		// After the data: fcopyfile stamps a quarantine value of its own on the copy, which this overwrites with the
		// source's exact value. Before the mode: an extended attribute cannot be written to a file whose mode is
		// read-only, not even through a descriptor opened for writing.
		try copyQuarantineAttribute(from: source, to: destination, fileSystem: fileSystem)
		// The copy gets the source's permission bits, like Node's fs.copyFile did (umask not applied).
		try systemCall { fchmod(destination, sourceStatus.st_mode & 0o777) }

		// Identity from the descriptor, now that the data is written: on exFAT and FAT32 an empty file has a made-up
		// inode number that changes with the first byte.
		let copyIdentity = FileIdentity(try status(ofDescriptor: destination))
		let storedName = try storedFileName(atPath: plan.destinationPath, identity: copyIdentity, fileSystem: fileSystem)
		guard isNFCName(storedName) else {
			throw UserFacingError(message: localized(Message.nameNotKeptInNFC))
		}

		// Closed here, with its result, and not by the `defer` above: some volumes (a network share, a quota) report
		// a write that failed late only now, and such a copy is removed and reported, as Node's fs.copyFile did.
		// After the name check, so the copy is still open while it is looked up by the inode this descriptor gave.
		destinationIsOpen = false
		try fileSystem.closeCopy(destination)

		return FileCopyPlan(
			sourcePath: plan.sourcePath,
			sourceName: plan.sourceName,
			destinationPath: joinPath(directoryName(ofPath: plan.destinationPath), storedName),
			destinationName: storedName,
			hasNumberSuffix: plan.hasNumberSuffix
		)
	} catch {
		// Remove through the NFC path that was written; the name readdir reports may not unlink on exFAT.
		// If even that fails, its error is the one reported: the user must hear that something was left behind.
		try removeFile(atPath: plan.destinationPath)
		throw error
	}
}

/// The stem the user typed, tidied: `baseName` is what was typed, `extension` the source's extension (with its dot).
func customStem(_ baseName: String, extension fileExtension: String) -> String {
	// Leading dots would hide the copy in Finder; trailing ones are dropped by Windows anyway.
	let stem = nfc(baseName)
		.removingLeadingScalars(while: isDotOrJavaScriptWhitespace)
		.removingTrailingScalars(while: isDotOrJavaScriptWhitespace)
	let sourceExtension = nfc(fileExtension).removingTrailingScalars { $0 == "." || $0 == " " }

	// Users often type the extension as well ("보고서.hwp"); it is appended anyway.
	// Compared and cut in UTF-16 code units, as JavaScript's endsWith and slice did. `hasSuffix` would also match a
	// canonically equivalent ending that is spelled differently, and then the cut would remove the wrong text.
	let stemUnits = Array(stem.utf16)
	let loweredStem = Array(stem.javaScriptLowercased().utf16)
	let loweredExtension = Array(sourceExtension.javaScriptLowercased().utf16)
	guard !sourceExtension.utf16.isEmpty, loweredStem.count >= loweredExtension.count,
	      loweredStem[(loweredStem.count - loweredExtension.count)...].elementsEqual(loweredExtension) else {
		return stem
	}

	// The cut uses the length of the extension as written, not as lowercased (the two differ for "İ"). Should it
	// fall inside a surrogate pair, the half that is left becomes U+FFFD, which is what Node wrote to disk for it.
	return String(decoding: stemUnits.dropLast(sourceExtension.utf16.count), as: UTF16.self)
}

private func isDotOrJavaScriptWhitespace(_ scalar: Unicode.Scalar) -> Bool {
	scalar == "." || isJavaScriptWhitespace(scalar)
}

// fcopyfile(COPYFILE_DATA) copies the bytes of the file and nothing else that matters here: no mode, no ACL, no
// Finder tags or other extended attributes.
private func copyData(from source: Int32, to destination: Int32) throws {
	while fcopyfile(source, destination, nil, copyfile_flags_t(COPYFILE_DATA)) != 0 {
		let code = errno
		guard code == EINTR else {
			throw SystemCallError(code: code)
		}

		// A signal stopped the copy part-way. fcopyfile continues from where the descriptors stand, so start over
		// from an empty copy instead of guessing how far it got.
		try systemCall { lseek(source, 0, SEEK_SET) }
		try systemCall { ftruncate(destination, 0) }
		try systemCall { lseek(destination, 0, SEEK_SET) }
	}
}

// Keep the download quarantine flag so an app or script copied by this tool is still checked by Gatekeeper.
// Read from and written to the open descriptors: the read-only original is not touched, and the value is carried over
// byte for byte.
private func copyQuarantineAttribute(from source: Int32, to destination: Int32, fileSystem: FileSystemAccess) throws {
	guard let value = try quarantineValue(of: source, fileSystem: fileSystem) else {
		return
	}

	do {
		try value.withUnsafeBytes { bytes in
			_ = try systemCall { fsetxattr(destination, quarantineAttribute, bytes.baseAddress, bytes.count, 0, 0) }
		}
	} catch {
		// Whatever the reason (a volume without extended attributes, no space left): a copy without the flag would
		// slip past Gatekeeper, so it is not kept.
		throw UserFacingError(message: localized(Message.quarantineNotCopied))
	}
}

/// The source's quarantine value, or nil when it has none.
private func quarantineValue(of descriptor: Int32, fileSystem: FileSystemAccess) throws -> [UInt8]? {
	// The size is asked first and the value read second; if the value grew in between (ERANGE), ask again.
	for _ in 0..<4 {
		guard let size = try? fileSystem.readAttribute(descriptor, quarantineAttribute, nil) else {
			// No such attribute (ENOATTR), a volume without extended attributes, or an attribute that may not even
			// be asked for: an ACL that denies reading extended attributes gives EACCES whether the file has the
			// flag or not. All of these are "nothing to carry over", as every failure of `xattr -p` was in the
			// Electron app; refusing would also refuse files that never had a flag.
			return nil
		}

		// At least one byte, so the buffer pointer is never nil (a nil buffer means "tell me the size" again).
		var value = [UInt8](repeating: 0, count: max(size, 1))
		do {
			let length = try value.withUnsafeMutableBytes { bytes in
				try fileSystem.readAttribute(descriptor, quarantineAttribute, bytes)
			}
			return Array(value.prefix(length))
		} catch let error as SystemCallError where error.code == ENOATTR {
			return nil
		} catch let error as SystemCallError where error.code == ERANGE {
			continue
		} catch {
			break
		}
	}

	// The attribute is there (its size was just reported) but its value could not be read: do not hand out a copy
	// that silently lost it.
	throw UserFacingError(message: localized(Message.quarantineNotCopied))
}

/// Returns the name exactly as the file system stored it, which may differ in normalization from `filePath`.
/// `identity` is the file's device and inode, taken by the caller from `stat` (source) or the open descriptor (copy).
private func storedFileName(atPath filePath: String, identity: FileIdentity, fileSystem: FileSystemAccess) throws -> String {
	let directory = directoryName(ofPath: filePath)
	let name = baseName(ofPath: filePath)
	let entries = try fileSystem.directoryEntries(directory)

	// Bytes, not `==`: an entry stored in the other normalization must not count as "the same name".
	if entries.contains(where: { $0.utf8.elementsEqual(name.utf8) }) {
		return name
	}

	// Normalization-insensitive volumes find the file under either spelling; match the entry by inode.
	// stat on the entry's path, not readdir's d_ino: for a symlink d_ino is the link's own number, and exFAT reports
	// a different d_ino on every listing of an empty file.
	let nfcName = nfc(name)
	for entry in entries where hasSameScalars(nfc(entry), nfcName) {
		let entryStatus = try status(atPath: joinPath(directory, entry))
		if FileIdentity(entryStatus) == identity {
			return entry
		}
	}

	return name
}

private func uniqueDestinationPath(_ firstCandidate: String, fileSystem: FileSystemAccess) -> (path: String, hasNumberSuffix: Bool) {
	if !fileSystem.entryExists(firstCandidate) {
		return (firstCandidate, false)
	}

	// " (n)" goes between the name and its extension. The candidate's own last dot decides, as path.parse did.
	let directory = directoryName(ofPath: firstCandidate)
	let (stem, fileExtension) = splitFileName(baseName(ofPath: firstCandidate))
	var counter = 1

	while true {
		let candidate = joinPath(directory, "\(stem) (\(counter))\(fileExtension)")
		if !fileSystem.entryExists(candidate) {
			return (candidate, true)
		}
		counter += 1
	}
}
