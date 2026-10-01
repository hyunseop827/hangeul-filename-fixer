// The system calls the copy engine uses, as thin wrappers.
//
// Every path reaches the kernel as the String's own UTF-8 bytes (`withCString`). That is what keeps an NFC name NFC:
// FileManager, URL, Data.write and NSString.fileSystemRepresentation all decompose the name first, and the file is
// then stored under the NFD spelling this app exists to get rid of. Names are read back with readdir and built from
// the raw bytes for the same reason.
import Darwin

/// A failed system call, kept as its errno until it is turned into a Korean message.
struct SystemCallError: Error, Equatable {
	let code: Int32
}

/// What identifies a file on this Mac whatever its path is spelled like: the volume and the inode.
struct FileIdentity: Equatable {
	let device: dev_t
	let inode: ino_t

	init(_ status: stat) {
		device = status.st_dev
		inode = status.st_ino
	}
}

/// The file-system operations the unit tests answer differently from the real disk. The app always uses `.real`.
/// - "Is this name taken?", to stage a file that appears right after the name was chosen.
/// - "What does this folder list?", to stage a volume that reports names decomposed.
/// - "What is in this extended attribute?", to stage a quarantine flag that is there but cannot be read.
/// - "Did the copy close without an error?", to stage a volume that reports a failed write only then.
/// No real volume can be made to do the last two on demand.
struct FileSystemAccess: Sendable {
	/// lstat: true when any entry has this name, including a folder or a symlink without a target.
	var entryExists: @Sendable (_ path: String) -> Bool
	/// readdir: the names in a folder exactly as the volume reports them, without "." and "..".
	var directoryEntries: @Sendable (_ directory: String) throws -> [String]
	/// fgetxattr: without a buffer, the size of the attribute's value; with one, the number of bytes read into it.
	var readAttribute: @Sendable (_ descriptor: Int32, _ name: String, _ buffer: UnsafeMutableRawBufferPointer?) throws -> Int = {
		try readExtendedAttribute(ofDescriptor: $0, named: $1, into: $2)
	}
	/// close(2) on the finished copy. Whether it throws or not, the descriptor is closed afterwards.
	var closeCopy: @Sendable (_ descriptor: Int32) throws -> Void = { try closeDescriptor($0) }

	static let real = FileSystemAccess(
		entryExists: { hasEntry(atPath: $0) },
		directoryEntries: { try listDirectory(atPath: $0) }
	)
}

/// Runs a system call and returns its result, or throws the errno it failed with (read before anything else can
/// change it). A call that a signal interrupted before it did anything (EINTR) is simply made again.
@discardableResult
func systemCall<Value: SignedInteger>(_ call: () -> Value) throws -> Value {
	while true {
		let result = call()
		if result != -1 {
			return result
		}

		let code = errno
		if code != EINTR {
			throw SystemCallError(code: code)
		}
	}
}

/// Runs a system call on the path's own UTF-8 bytes. A path with a NUL in it would be cut there by C and name another
/// file, so it fails with EINVAL instead of reaching the kernel.
@discardableResult
private func systemCall(onPath path: String, _ call: (UnsafePointer<CChar>) -> Int32) throws -> Int32 {
	if path.utf8.contains(0) {
		throw SystemCallError(code: EINVAL)
	}

	return try path.withCString { pointer in try systemCall { call(pointer) } }
}

/// stat(2): follows symlinks, so a link to a regular file counts as that file.
func status(atPath path: String) throws -> stat {
	var status = stat()
	try systemCall(onPath: path) { stat($0, &status) }
	return status
}

func status(ofDescriptor descriptor: Int32) throws -> stat {
	var status = stat()
	try systemCall { fstat(descriptor, &status) }
	return status
}

func isRegularFile(_ status: stat) -> Bool {
	(status.st_mode & S_IFMT) == S_IFREG
}

// Unlike a check that follows links, lstat also counts a dangling symlink as taken, which O_EXCL would refuse.
// A name that is too long to exist (ENAMETOOLONG) is "free" here; creating it then fails with that error.
func hasEntry(atPath path: String) -> Bool {
	var status = stat()
	return (try? systemCall(onPath: path) { lstat($0, &status) }) != nil
}

func isReadable(atPath path: String) -> Bool {
	(try? systemCall(onPath: path) { access($0, R_OK) }) != nil
}

func openDescriptor(atPath path: String, flags: Int32, mode: mode_t = 0) throws -> Int32 {
	try systemCall(onPath: path) { open($0, flags, mode) }
}

/// fgetxattr(2) on an open file: without a buffer, the size of the attribute's value; with one, the number of bytes
/// read into it. A file without the attribute fails with ENOATTR.
func readExtendedAttribute(ofDescriptor descriptor: Int32, named name: String, into buffer: UnsafeMutableRawBufferPointer?) throws -> Int {
	try systemCall { fgetxattr(descriptor, name, buffer?.baseAddress, buffer?.count ?? 0, 0, 0) }
}

/// close(2), with its result: a network share or a volume with a quota may report a write that failed late (EIO,
/// ENOSPC, EDQUOT) only when the file is closed.
///
/// Not through `systemCall`: close must never be called again after EINTR. The descriptor is closed by then, and a
/// second close could hit a file another thread has just opened. An interrupted close is no error (libuv, and with
/// it Node's fs.copyFile, treated EINTR and EINPROGRESS the same way).
func closeDescriptor(_ descriptor: Int32) throws {
	guard close(descriptor) == -1 else {
		return
	}

	let code = errno
	if code != EINTR, code != EINPROGRESS {
		throw SystemCallError(code: code)
	}
}

/// unlink(2). A file that is already gone is not an error.
func removeFile(atPath path: String) throws {
	do {
		try systemCall(onPath: path) { unlink($0) }
	} catch let error as SystemCallError where error.code == ENOENT {
		return
	}
}

/// The names in a folder, each built from the raw bytes readdir returned. No Foundation in between: the names must
/// come back exactly as the volume reports them, NFC or NFD.
func listDirectory(atPath directory: String) throws -> [String] {
	if directory.utf8.contains(0) {
		throw SystemCallError(code: EINVAL)
	}

	var stream: UnsafeMutablePointer<DIR>?
	var openError: Int32 = 0
	repeat {
		(stream, openError) = directory.withCString { pointer in
			let opened = opendir(pointer)
			return (opened, opened == nil ? errno : 0)
		}
	} while stream == nil && openError == EINTR
	guard let stream else {
		throw SystemCallError(code: openError)
	}
	defer { closedir(stream) }

	var names: [String] = []

	while true {
		// readdir returns nil both at the end and on an error; only errno tells them apart.
		errno = 0
		guard let entry = readdir(stream) else {
			let code = errno
			if code == EINTR {
				continue
			}
			if code != 0 {
				throw SystemCallError(code: code)
			}
			break
		}

		let length = Int(entry.pointee.d_namlen)
		let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
			String(decoding: UnsafeRawBufferPointer(start: pointer, count: length), as: UTF8.self)
		}
		if hasSameScalars(name, ".") || hasSameScalars(name, "..") {
			continue
		}

		names.append(name)
	}

	return names
}
