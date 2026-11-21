//
//  AltStore+Async.swift
//  AltStore
//
//  Created by Riley Testut on 3/23/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//
@preconcurrency import UIKit
import CoreData

public extension NSManagedObjectContext
{
    func performAsync<T>(_ closure: @escaping () -> T) async -> T
    {
        await self.perform(schedule: .immediate) {
            closure()
        }
    }
    func performAsync<T>(_ closure: @escaping () throws -> T) async throws -> T
    {
        try await self.perform(schedule: .immediate) {
            try closure()
        }
    }
}

public extension UIViewController
{
    @MainActor
    func presentAlert(title: String, message: String?, action: UIAlertAction? = nil) async
    {
        let action = action ?? .ok
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: action.title, style: action.style) { _ in
                continuation.resume()
            })
            self.present(alertController, animated: true)
        }
    }
    @MainActor
    func presentConfirmationAlert(title: String, message: String, primaryAction: UIAlertAction, cancelAction: UIAlertAction? = nil) async throws
    {
        _ = try await self.presentConfirmationAlert(title: title, message: message, actions: [primaryAction], cancelAction: cancelAction)
    }
    @MainActor
    func presentConfirmationAlert(title: String, message: String, actions: [UIAlertAction], cancelAction: UIAlertAction? = nil) async throws -> UIAlertAction
    {
        let cancelAction = cancelAction ?? .cancel
        let action = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIAlertAction, Error>) in
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: cancelAction.title, style: cancelAction.style) { _ in
                continuation.resume(throwing: CancellationError())
            })
            for action in actions
            {
                alertController.addAction(UIAlertAction(title: action.title, style: action.style) { alertAction in
                    continuation.resume(returning: action)
                })
            }
            self.present(alertController, animated: true)
        }
        return action
    }
}
