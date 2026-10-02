// A block observer of a notification that takes itself out of the notification center when it goes away.
//
// Whoever keeps one needs no `deinit` of its own: a view's or a window controller's `deinit` runs outside the main
// actor and may not touch what the actor isolates, and without it an observer would stay registered after its owner
// is gone (AppKit does not end the editing of a text field when its window is closed, for example).
import Foundation

final class NotificationObservation {
	private let center: NotificationCenter
	private let token: NSObjectProtocol

	/// `handler` is called on the thread that posts the notification, for as long as this object lives.
	init(_ name: Notification.Name, object: AnyObject? = nil, center: NotificationCenter = .default, handler: @escaping @Sendable (Notification) -> Void) {
		self.center = center
		token = center.addObserver(forName: name, object: object, queue: nil, using: handler)
	}

	deinit {
		center.removeObserver(token)
	}
}
