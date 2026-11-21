//
//  PresenterProvider.swift
//  SideStore
//
//  Created by Magesh K on 4/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import UIKit

typealias PresenterProvider = @MainActor @Sendable () -> UIViewController?
