//
//  HeaderContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/10/23.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
@preconcurrency import UIKit

import Nuke

protocol ScrollableContentViewController: UIViewController
{
    var scrollView: UIScrollView { get }
}

class HeaderContentViewController<Header: UIView, Content: ScrollableContentViewController> : UIViewController,
                                                                                              UIAdaptivePresentationControllerDelegate,
                                                                                              UIScrollViewDelegate,
                                                                                              UIGestureRecognizerDelegate
{
    var tintColor: UIColor? {
        didSet {
            guard self.isViewLoaded else { return }
            self.view.tintColor = self.tintColor?.adjustedForDisplay
            self.update()
        }
    }
    private(set) var headerView: Header!
    private(set) var contentViewController: Content!
    private(set) var backButton: VibrantButton!
    private(set) var backgroundImageView: UIImageView!
    private(set) var navigationBarNameLabel: UILabel!
    private(set) var navigationBarIconView: UIImageView!
    private(set) var navigationBarTitleView: UIStackView!
    private(set) var navigationBarButton: PillButton!
    private var scrollView: UIScrollView!
    private var headerScrollView: UIScrollView!
    private var headerContainerView: UIView!
    private var backgroundBlurView: UIVisualEffectView!
    private var contentViewControllerShadowView: UIView!
    private var ignoreBackGestureRecognizer: UIPanGestureRecognizer!
    private var blurAnimator: UIViewPropertyAnimator?
    private var navigationBarAnimator: UIViewPropertyAnimator?
    private var contentSizeObservation: NSKeyValueObservation?
    private var _shouldResetLayout = false
    private var _backgroundBlurEffect: UIBlurEffect?
    private var _backgroundBlurTintColor: UIColor?
    private var isViewingHeader: Bool {
        let isViewingHeader = (self.headerScrollView.contentOffset.x != self.headerScrollView.contentInset.left)
        return isViewingHeader
    }
    #if !os(tvOS)
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 17, *)
        {
            return .default
        }
        else
        {
            return _preferredStatusBarStyle
        }
    }
    private var _preferredStatusBarStyle: UIStatusBarStyle = .default
    #endif
    init()
    {
        super.init(nibName: nil, bundle: nil)
    }
    deinit
    {
        self.blurAnimator?.stopAnimation(true)
        self.navigationBarAnimator?.stopAnimation(true)
    }
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
    }
    func makeContentViewController() -> Content
    {
        fatalError()
    }
    func makeHeaderView() -> Header
    {
        fatalError()
    }
    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.view.backgroundColor = .altBackground
        self.view.clipsToBounds = true
        #if !os(tvOS)
        self.navigationItem.largeTitleDisplayMode = .never
        #endif
        self.navigationController?.presentationController?.delegate = self
        self.backgroundImageView = UIImageView(frame: .zero)
        self.backgroundImageView.contentMode = .scaleAspectFill
        self.view.addSubview(self.backgroundImageView)
        let blurEffect = UIBlurEffect(style: .regular)
        self.backgroundBlurView = UIVisualEffectView(effect: blurEffect)
        self.view.addSubview(self.backgroundBlurView, pinningEdgesWith: .zero)
        self.headerContainerView = UIView(frame: .zero)
        self.view.addSubview(self.headerContainerView, pinningEdgesWith: .zero)
        self.ignoreBackGestureRecognizer = UIPanGestureRecognizer(target: self, action: nil)
        self.ignoreBackGestureRecognizer.delegate = self
        self.headerContainerView.addGestureRecognizer(self.ignoreBackGestureRecognizer)
        #if !os(tvOS)
        self.navigationController?.interactivePopGestureRecognizer?.require(toFail: self.ignoreBackGestureRecognizer) 
        #endif
        self.headerScrollView = UIScrollView(frame: .zero)
        self.headerScrollView.delegate = self
        #if !os(tvOS)
        self.headerScrollView.isPagingEnabled = true
        #endif
        self.headerScrollView.clipsToBounds = false
        self.headerScrollView.indicatorStyle = .white
        self.headerScrollView.showsVerticalScrollIndicator = false
        self.headerContainerView.addSubview(self.headerScrollView)
        self.headerContainerView.addGestureRecognizer(self.headerScrollView.panGestureRecognizer) 
        self.headerView = self.makeHeaderView()
        self.headerScrollView.addSubview(self.headerView)
        let imageConfiguration = UIImage.SymbolConfiguration(weight: .semibold)
        let image = UIImage(systemName: "chevron.backward", withConfiguration: imageConfiguration)
        self.backButton = VibrantButton(type: .system)
        self.backButton.image = image
        self.backButton.tintColor = self.tintColor
        self.backButton.sizeToFit()
        self.backButton.addTarget(self.navigationController, action: #selector(UINavigationController.popViewController(animated:)), for: .primaryActionTriggered)
        self.contentViewController = self.makeContentViewController()
        self.contentViewController.view.frame = self.view.bounds
        self.contentViewController.view.layer.cornerRadius = 38
        self.contentViewController.view.layer.masksToBounds = true
        self.addChild(self.contentViewController)
        self.view.addSubview(self.contentViewController.view)
        self.contentViewController.didMove(toParent: self)
        self.contentViewControllerShadowView = UIView()
        self.contentViewControllerShadowView.backgroundColor = .altBackground
        self.contentViewControllerShadowView.layer.cornerRadius = 38
        self.contentViewControllerShadowView.layer.shadowColor = UIColor.black.cgColor
        self.contentViewControllerShadowView.layer.shadowOffset = CGSize(width: 0, height: -1)
        self.contentViewControllerShadowView.layer.shadowRadius = 10
        self.contentViewControllerShadowView.layer.shadowOpacity = 0.3
        self.view.insertSubview(self.contentViewControllerShadowView, belowSubview: self.contentViewController.view)
        self.scrollView = UIScrollView(frame: CGRect(origin: .zero, size: self.view.bounds.size))
        self.scrollView.delegate = self
        self.scrollView.isUserInteractionEnabled = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.view.addSubview(self.scrollView, pinningEdgesWith: .zero)
        self.view.addGestureRecognizer(self.scrollView.panGestureRecognizer)
        self.contentViewController.scrollView.panGestureRecognizer.require(toFail: self.scrollView.panGestureRecognizer)
        self.contentViewController.scrollView.showsVerticalScrollIndicator = false
        self.contentViewController.scrollView.contentInsetAdjustmentBehavior = .never
        self.navigationBarNameLabel = UILabel(frame: .zero)
        self.navigationBarNameLabel.font = UIFont.boldSystemFont(ofSize: 17) 
        self.navigationBarNameLabel.text = self.title
        self.navigationBarNameLabel.sizeToFit()
        self.navigationBarIconView = UIImageView(frame: .zero)
        self.navigationBarIconView.clipsToBounds = true
        self.navigationBarTitleView = UIStackView(arrangedSubviews: [self.navigationBarIconView, self.navigationBarNameLabel])
        self.navigationBarTitleView.axis = .horizontal
        self.navigationBarTitleView.spacing = 8
        self.navigationBarButton = PillButton(type: .system)
        self.navigationBarButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.navigationBarButton.setContentHuggingPriority(.required, for: .horizontal)
        if #available(iOS 16.0, *) {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.navigationBarButton)
        } else {
            let buttonContainerView = UIView()
            buttonContainerView.addSubview(self.navigationBarButton, pinningEdgesWith: .zero)
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: buttonContainerView)
        }
        NSLayoutConstraint.activate([
            self.navigationBarIconView.widthAnchor.constraint(equalToConstant: 35),
            self.navigationBarIconView.heightAnchor.constraint(equalTo: self.navigationBarIconView.widthAnchor)
        ])
        let size = self.navigationBarTitleView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.navigationBarTitleView.bounds.size = size
        self.navigationItem.titleView = self.navigationBarTitleView
        self._backgroundBlurEffect = self.backgroundBlurView.effect as? UIBlurEffect
        self._backgroundBlurTintColor = self.backgroundBlurView.contentView.backgroundColor
        self.contentSizeObservation = self.contentViewController.scrollView.observe(\.contentSize, options: [.new, .old]) { [weak self] (scrollView, change) in
            guard let size = change.newValue, let previousSize = change.oldValue, size != previousSize else { return }
            self?.view.setNeedsLayout()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(HeaderContentViewController.willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HeaderContentViewController.didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        self.setContentScrollView(self.scrollView)
        self.hideNavigationBar()
        self.view.tintColor = self.tintColor?.adjustedForDisplay
    }
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        self.prepareBlur()
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        self.headerScrollView.flashScrollIndicators()
        self.update()
    }
    override func viewIsAppearing(_ animated: Bool) 
    {
        super.viewIsAppearing(animated)
        self.headerView.setNeedsLayout()
    }
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        if self._shouldResetLayout
        {
            self.prepareBlur()

            self.resetNavigationBarAnimation()
            self._shouldResetLayout = false
        }
        let statusBarHeight: Double
        #if !os(tvOS)
        if let navigationController, navigationController.presentingViewController != nil, navigationController.modalPresentationStyle != .fullScreen
        {
            statusBarHeight = 20
        }
        else if let statusBarManager = (self.view.window ?? self.presentedViewController?.view.window)?.windowScene?.statusBarManager
        {
            statusBarHeight = statusBarManager.statusBarFrame.height
        }
        else
        {
            statusBarHeight = 0
        }
        #else
        statusBarHeight = 0
        #endif
        let cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
        let inset = 15 as CGFloat
        let padding = 20 as CGFloat
        let backButtonSize = self.backButton.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
        let largestBackButtonDimension = max(backButtonSize.width, backButtonSize.height) 
        var backButtonFrame = CGRect(x: inset, y: statusBarHeight, width: largestBackButtonDimension, height: largestBackButtonDimension)
        var headerFrame = CGRect(x: inset, y: 0, width: self.view.bounds.width - inset * 2, height: self.headerView.bounds.height)
        var contentFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        var backgroundIconFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.width)
        let backButtonPadding = 8.0
        let minimumHeaderY = backButtonFrame.maxY + backButtonPadding
        let headerTopY = minimumHeaderY + 56.0 
        let minimumContentHeight = minimumHeaderY + headerFrame.height + padding
        let maximumContentY = headerTopY + headerFrame.height + padding
        contentFrame.origin.y = maximumContentY - self.scrollView.contentOffset.y
        headerFrame.origin.y = contentFrame.origin.y - padding - headerFrame.height
        let height = max(contentFrame.origin.y + cornerRadius * 2, backgroundIconFrame.height)
        backgroundIconFrame.size.height = height
        self.updateBlur()
        let showNavigationBarThreshold = (maximumContentY - minimumContentHeight) + backButtonFrame.origin.y
        if self.scrollView.contentOffset.y > showNavigationBarThreshold
        {
            if self.navigationBarAnimator == nil
            {
                self.prepareNavigationBarAnimation()
            }
            let difference = self.scrollView.contentOffset.y - showNavigationBarThreshold
            let range: Double
            if self.presentingViewController == nil && self.parent?.presentingViewController == nil
            {
                range = (headerFrame.height + padding) - (self.navigationController?.navigationBar.bounds.height ?? self.view.safeAreaInsets.top)
            }
            else
            {
                range = maximumContentY - (maximumContentY - padding - headerFrame.height) - inset
            }
            let fractionComplete = min(difference, range) / range
            self.navigationBarAnimator?.fractionComplete = fractionComplete
        }
        else
        {
            self.navigationBarAnimator?.fractionComplete = 0.0
            self.resetNavigationBarAnimation()
        }
        let beginMovingBackButtonThreshold = (maximumContentY - minimumContentHeight)
        if self.scrollView.contentOffset.y > beginMovingBackButtonThreshold
        {
            let difference = self.scrollView.contentOffset.y - beginMovingBackButtonThreshold
            backButtonFrame.origin.y -= difference
        }
        let pinContentToTopThreshold = maximumContentY
        if self.scrollView.contentOffset.y > pinContentToTopThreshold
        {
            contentFrame.origin.y = 0
            backgroundIconFrame.origin.y = 0
            let difference = self.scrollView.contentOffset.y - pinContentToTopThreshold
            self.contentViewController.scrollView.contentOffset.y = -self.contentViewController.scrollView.contentInset.top + difference
        }
        else
        {
            self.contentViewController.scrollView.contentOffset.y = -self.contentViewController.scrollView.contentInset.top
        }

        backgroundIconFrame.origin.y = (contentFrame.origin.y / 2) - backgroundIconFrame.height / 2
        self.contentViewController.view.frame = contentFrame
        self.contentViewControllerShadowView.frame = contentFrame
        self.backgroundImageView.frame = backgroundIconFrame
        self.backButton.frame = backButtonFrame
        self.backButton.layer.cornerRadius = backButtonFrame.height / 2
        self.headerView.frame = CGRect(origin: .zero, size: headerFrame.size)
        self.headerScrollView.frame = headerFrame
        self.headerScrollView.contentSize = CGSize(width: headerFrame.width * 2, height: headerFrame.height)
        self.scrollView.verticalScrollIndicatorInsets.top = statusBarHeight
        self.headerScrollView.horizontalScrollIndicatorInsets.bottom = -12
        let contentOffset = self.scrollView.contentOffset
        var contentSize = self.contentViewController.scrollView.contentSize
        contentSize.height += self.contentViewController.scrollView.contentInset.top + self.contentViewController.scrollView.contentInset.bottom
        contentSize.height += maximumContentY
        contentSize.height = max(contentSize.height, self.view.bounds.height + maximumContentY - (self.navigationController?.navigationBar.bounds.height ?? 0))
        self.scrollView.contentSize = contentSize
        self.scrollView.contentOffset = contentOffset
    }
    func update()
    {
    }
    @objc private func willEnterForeground(_ notification: Notification)
    {
        guard let navigationController = self.navigationController, navigationController.topViewController == self else { return }
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
    }
    @objc private func didBecomeActive(_ notification: Notification)
    {
        guard let navigationController = self.navigationController, navigationController.topViewController == self else { return }
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
    }
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool
    {
        return false
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView)
    {
        switch scrollView
        {
        case self.scrollView: self.view.setNeedsLayout()
        case self.headerScrollView:
            self.headerScrollView.showsHorizontalScrollIndicator = false
            self.updateBlur()
        default: break
        }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    {
        let disableBackGesture = self.isViewingHeader
        return disableBackGesture
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        return true
    }

    #if os(tvOS)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?)
    {
        guard let press = presses.first, press.type == .menu else {
            super.pressesBegan(presses, with: event)
            return
        }
        if let navigationController = self.navigationController, navigationController.viewControllers.count > 1
        {
            navigationController.popViewController(animated: true)
        }
        else if self.presentingViewController != nil
        {
            self.dismiss(animated: true)
        }
        else
        {
            super.pressesBegan(presses, with: event)
        }
    }
    #endif
}

private extension HeaderContentViewController
{
    func showNavigationBar()
    {
        self.navigationBarIconView.alpha = 1.0
        self.navigationBarNameLabel.alpha = 1.0
        self.navigationBarButton.alpha = 1.0
        self.updateNavigationBarAppearance(isHidden: false)
        #if !os(tvOS)
        if self.traitCollection.userInterfaceStyle == .dark
        {
            self._preferredStatusBarStyle = .lightContent
        }
        else
        {
            self._preferredStatusBarStyle = .default
        }
        if #unavailable(iOS 17)
        {
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        }
        #endif
    }
    func hideNavigationBar()
    {
        self.navigationBarIconView.alpha = 0.0
        self.navigationBarNameLabel.alpha = 0.0
        self.navigationBarButton.alpha = 1.0
        self.updateNavigationBarAppearance(isHidden: true)
        #if !os(tvOS)
        self._preferredStatusBarStyle = .lightContent
        if #unavailable(iOS 17)
        {
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        }
        #endif
    }
    func updateNavigationBarAppearance(isHidden: Bool)
    {
        #if !os(tvOS)
        let barAppearance = self.navigationItem.standardAppearance as? NavigationBarAppearance ?? NavigationBarAppearance()
        if isHidden
        {
            barAppearance.configureWithTransparentBackground()
        }
        else
        {
            barAppearance.configureWithDefaultBackground()
        }
        barAppearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
        let dynamicColor = UIColor { traitCollection in
            var tintColor = self.tintColor ?? .altPrimary
            if traitCollection.userInterfaceStyle == .dark && tintColor.isTooDark
            {
                tintColor = .white
            }
            else
            {
                tintColor = tintColor.adjustedForDisplay
            }
            return tintColor
        }
        let tintColor = dynamicColor
        barAppearance.configureWithTintColor(tintColor)
        self.navigationItem.standardAppearance = barAppearance
        self.navigationItem.scrollEdgeAppearance = barAppearance
        #endif
    }
    func prepareBlur()
    {
        if let animator = self.blurAnimator
        {
            animator.stopAnimation(true)
        }
        self.backgroundBlurView.effect = self._backgroundBlurEffect
        self.backgroundBlurView.contentView.backgroundColor = self._backgroundBlurTintColor
        self.blurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.backgroundBlurView.effect = nil
            self?.backgroundBlurView.contentView.backgroundColor = .clear
        }

        self.blurAnimator?.startAnimation()
        self.blurAnimator?.pauseAnimation()
    }
    func updateBlur()
    {
        let minimumBlurFraction = 0.3 as CGFloat
        if self.isViewingHeader
        {
            let maximumX = self.headerScrollView.bounds.width
            let fraction = self.headerScrollView.contentOffset.x / maximumX
            let fractionComplete = (fraction * (1.0 - minimumBlurFraction)) + minimumBlurFraction
            self.blurAnimator?.fractionComplete = fractionComplete
        }
        else if self.scrollView.contentOffset.y < 0
        {
            let range = 75 as CGFloat
            let difference = -self.scrollView.contentOffset.y
            let fraction = min(difference, range) / range
            let fractionComplete = (fraction * (1.0 - minimumBlurFraction)) + minimumBlurFraction
            self.blurAnimator?.fractionComplete = fractionComplete
        }
        else
        {
            self.blurAnimator?.fractionComplete = minimumBlurFraction
        }
    }
    func prepareNavigationBarAnimation()
    {
        self.resetNavigationBarAnimation()
        self.navigationBarAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.showNavigationBar()
            self?.navigationController?.navigationBar.layoutIfNeeded()
            self?.contentViewController.view.layer.cornerRadius = 0
        }
        self.navigationBarAnimator?.startAnimation()
        self.navigationBarAnimator?.pauseAnimation()
        self.update()
    }
    func resetNavigationBarAnimation()
    {
        guard self.navigationBarAnimator != nil else { return }
        self.navigationBarAnimator?.stopAnimation(true)
        self.navigationBarAnimator = nil
        self.hideNavigationBar()
        self.contentViewController.view.layer.cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
    }
}
