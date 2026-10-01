// The Korean texts the copy engine reports. They are shown to the user as they are.
import Darwin
import Foundation

/// A failure worded for the user, in Korean. The app shows `message` unchanged.
public struct UserFacingError: Error, Sendable {
	public let message: String

	public init(message: String) {
		self.message = message
	}
}

extension UserFacingError: LocalizedError {
	public var errorDescription: String? { message }
}

/// Shown when the selected item is a folder, an app bundle or no longer there.
public let notRegularFileMessage = localized(Message.notRegularFile)

/// Every text of this module, as written in the source. Each is also its own key in the app's Localizable.strings.
enum Message {
	static let notRegularFile = "일반 파일이 아니거나(폴더·앱 등) 더 이상 없습니다. 파일을 다시 선택하세요."
	static let sourceNotReadable = "원본 파일을 읽을 권한이 없습니다. 파일 권한을 확인하세요."
	static let quarantineNotCopied = "다운로드 보안 표시(quarantine)를 사본에 옮기지 못했습니다. 다른 저장 위치를 선택하세요."
	static let nameNotKeptInNFC = "이 저장 위치는 파일명을 NFC로 유지하지 못합니다(외장 드라이브 등). 내장 디스크의 다른 폴더를 선택하세요."
	static let notWritable = "이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요."
	static let readOnlyLocation = "읽기 전용 위치에는 저장할 수 없습니다. 다른 저장 위치를 선택하세요."
	static let noSpaceLeft = "저장 공간이 부족합니다."
	static let notFound = "원본 파일이나 저장 위치를 찾을 수 없습니다. 파일을 다시 선택하세요."
	static let nameTooLong = "파일명이 너무 깁니다. 더 짧은 이름을 입력하세요."
	static let nameJustTaken = "같은 이름의 파일이 방금 생겼습니다. 다시 시도하세요."
	/// Followed by the error's symbolic name in parentheses, e.g. "사본을 만들지 못했습니다. (EIO)".
	static let copyFailed = "사본을 만들지 못했습니다."

	static let all = [
		notRegularFile, sourceNotReadable, quarantineNotCopied, nameNotKeptInNFC, notWritable, readOnlyLocation,
		noSpaceLeft, notFound, nameTooLong, nameJustTaken, copyFailed
	]
}

/// Looks a text up in the app's Localizable.strings, where the key is the Korean text itself. Without that table
/// (unit tests, a command-line build) the text comes back unchanged.
func localized(_ text: String) -> String {
	Bundle.main.localizedString(forKey: text, value: text, table: nil)
}

/// The message for a failed system call while copying. Errors without a message of their own are named, so a report
/// from a user says what happened.
func userFacingError(forErrno code: Int32) -> UserFacingError {
	switch code {
	case EACCES, EPERM:
		return UserFacingError(message: localized(Message.notWritable))
	case EROFS:
		return UserFacingError(message: localized(Message.readOnlyLocation))
	case ENOSPC:
		return UserFacingError(message: localized(Message.noSpaceLeft))
	case ENOENT:
		return UserFacingError(message: localized(Message.notFound))
	case ENAMETOOLONG:
		return UserFacingError(message: localized(Message.nameTooLong))
	case EEXIST:
		return UserFacingError(message: localized(Message.nameJustTaken))
	default:
		return UserFacingError(message: "\(localized(Message.copyFailed)) (\(errnoName(code)))")
	}
}

/// The symbolic name of an errno value, as Node printed it in `error.code` ("ENOTDIR", "EIO", "ENOTCONN", …).
func errnoName(_ code: Int32) -> String {
	switch code {
	// Every errno Node 22 (libuv) has a name for on macOS, in the order of <sys/errno.h>. The seven with a message of
	// their own are listed too, so the table is complete.
	case EPERM: return "EPERM"
	case ENOENT: return "ENOENT"
	case ESRCH: return "ESRCH"
	case EINTR: return "EINTR"
	case EIO: return "EIO"
	case ENXIO: return "ENXIO"
	case E2BIG: return "E2BIG"
	case ENOEXEC: return "ENOEXEC"
	case EBADF: return "EBADF"
	case ENOMEM: return "ENOMEM"
	case EACCES: return "EACCES"
	case EFAULT: return "EFAULT"
	case EBUSY: return "EBUSY"
	case EEXIST: return "EEXIST"
	case EXDEV: return "EXDEV"
	case ENODEV: return "ENODEV"
	case ENOTDIR: return "ENOTDIR"
	case EISDIR: return "EISDIR"
	case EINVAL: return "EINVAL"
	case ENFILE: return "ENFILE"
	case EMFILE: return "EMFILE"
	case ENOTTY: return "ENOTTY"
	case ETXTBSY: return "ETXTBSY"
	case EFBIG: return "EFBIG"
	case ENOSPC: return "ENOSPC"
	case ESPIPE: return "ESPIPE"
	case EROFS: return "EROFS"
	case EMLINK: return "EMLINK"
	case EPIPE: return "EPIPE"
	case ERANGE: return "ERANGE"
	case EAGAIN: return "EAGAIN"
	case EALREADY: return "EALREADY"
	case ENOTSOCK: return "ENOTSOCK"
	case EDESTADDRREQ: return "EDESTADDRREQ"
	case EMSGSIZE: return "EMSGSIZE"
	case EPROTOTYPE: return "EPROTOTYPE"
	case ENOPROTOOPT: return "ENOPROTOOPT"
	case EPROTONOSUPPORT: return "EPROTONOSUPPORT"
	case ESOCKTNOSUPPORT: return "ESOCKTNOSUPPORT"
	case ENOTSUP: return "ENOTSUP"
	case EAFNOSUPPORT: return "EAFNOSUPPORT"
	case EADDRINUSE: return "EADDRINUSE"
	case EADDRNOTAVAIL: return "EADDRNOTAVAIL"
	case ENETDOWN: return "ENETDOWN"
	case ENETUNREACH: return "ENETUNREACH"
	case ECONNABORTED: return "ECONNABORTED"
	case ECONNRESET: return "ECONNRESET"
	case ENOBUFS: return "ENOBUFS"
	case EISCONN: return "EISCONN"
	case ENOTCONN: return "ENOTCONN"
	case ESHUTDOWN: return "ESHUTDOWN"
	case ETIMEDOUT: return "ETIMEDOUT"
	case ECONNREFUSED: return "ECONNREFUSED"
	case ELOOP: return "ELOOP"
	case ENAMETOOLONG: return "ENAMETOOLONG"
	case EHOSTDOWN: return "EHOSTDOWN"
	case EHOSTUNREACH: return "EHOSTUNREACH"
	case ENOTEMPTY: return "ENOTEMPTY"
	case ENOSYS: return "ENOSYS"
	case EFTYPE: return "EFTYPE"
	case EOVERFLOW: return "EOVERFLOW"
	case ECANCELED: return "ECANCELED"
	case EILSEQ: return "EILSEQ"
	case ENODATA: return "ENODATA"
	case EPROTO: return "EPROTO"
	// Node had no name for these and showed "Unknown system error -69"; the name from <sys/errno.h> says more.
	case EDEADLK: return "EDEADLK"
	case EDQUOT: return "EDQUOT"
	case ESTALE: return "ESTALE"
	case ENOATTR: return "ENOATTR"
	case EOPNOTSUPP: return "EOPNOTSUPP"
	default: return "errno \(code)"
	}
}
