//
//  UpdateCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
@preconcurrency import UIKit

extension UpdateCollectionViewCell
{
    enum Mode
    {
        case collapsed
        case expanded
    }
}

@objc final class UpdateCollectionViewCell: UICollectionViewCell
{
    var bundleIdentifier: String?
    var mode: Mode = .expanded {
        didSet {
            switch self.mode {
            case .collapsed:
                self.versionDescriptionTextView.isCollapsed = true
            case .expanded:
                self.versionDescriptionTextView.isCollapsed = false
            }
            self.setNeedsLayout()
        }
    }
    @IBOutlet var bannerView: AppBannerView!

    @IBOutlet var versionDescriptionTextView: CollapsingMarkdownView!
    @IBOutlet private var blurView: UIVisualEffectView!
    private var originalTintColor: UIColor?
    override func awakeFromNib()
    {
        super.awakeFromNib()
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentView.preservesSuperviewLayoutMargins = true
        self.bannerView.backgroundEffectView.isHidden = true
        self.blurView.layer.cornerRadius = 20
        self.blurView.layer.masksToBounds = true
        self.update()
    }
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        if self.tintAdjustmentMode != .dimmed
        {
            self.originalTintColor = self.tintColor
        }
        self.update()
    }
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes)
    {
        let animator = UIViewPropertyAnimator(springTimingParameters: UISpringTimingParameters()) {
            self.layoutIfNeeded()
        }
        animator.startAnimation()
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        let view = super.hitTest(point, with: event)
        if view == self.versionDescriptionTextView
        {
            return self
        }
        else
        {
            return view
        }
    }

}

private extension UpdateCollectionViewCell
{
    func update()
    {
        switch self.mode
        {
        case .collapsed: self.versionDescriptionTextView.isCollapsed = true
        case .expanded: self.versionDescriptionTextView.isCollapsed = false
        }
        self.blurView.backgroundColor = self.originalTintColor ?? self.tintColor
        self.bannerView.button.progressTintColor = self.originalTintColor ?? self.tintColor
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
}
