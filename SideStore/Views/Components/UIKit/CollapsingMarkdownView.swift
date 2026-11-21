//
//  CollapsingMarkdownView.swift
//  SideStore
//
//  Created by Magesh K on 27/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
@preconcurrency import UIKit
#if !os(tvOS)
import MarkdownKit
#endif

#if !os(tvOS)
struct MarkdownManager
{
    struct Fonts{
        static let body: UIFont     = .systemFont(ofSize: UIFont.systemFontSize)

        static let header: UIFont   = .boldSystemFont(ofSize: 14)
        static let list: UIFont     = .systemFont(ofSize: 14)
        static let bold: UIFont     = .boldSystemFont(ofSize: 14)
        static let italic: UIFont   = .italicSystemFont(ofSize: 14)
        static let quote: UIFont    = .italicSystemFont(ofSize: 14)
    }
    struct Color{
        static let header = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
        }
        static let bold = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor.lightText : UIColor.darkText
        }
    }
    static var enabledElements: MarkdownParser.EnabledElements {
        [
            .header,
            .list,
            .quote,
            .code,
            .link,
            .bold,
            .italic,
        ]
    }
    var markdownParser: MarkdownParser {
        MarkdownParser(
            font: Self.Fonts.body,
            color: Self.Color.bold
        )
    }
}
#endif

final class CollapsingMarkdownView: UIView {
    var didToggleCollapse: (() -> Void)?
    var isCollapsed = true {
        didSet {
            guard self.isCollapsed != oldValue else { return }
            self.updateCollapsedState()
        }
    }
    var maximumNumberOfLines = 3 {
        didSet {
            self.checkIfNeedsCollapsing()
            self.updateCollapsedState()
            self.setNeedsLayout()
        }
    }
    var text: String = "" {
        didSet {
            self.updateMarkdownContent()
            self.setNeedsLayout()
        }
    }
    var lineSpacing: Double = 2 {
        didSet {
            self.setNeedsLayout()
        }
    }
    let toggleButton = UIButton(type: .system)
    private let textView = UITextView()
    #if !os(tvOS)
    private let markdownParser = MarkdownManager().markdownParser
    #endif
    private var previousSize: CGSize?
    private var actualLineCount: Int = 0
    private var needsCollapsing = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }
    override func awakeFromNib() {
        super.awakeFromNib()
        initialize()
    }
    private func checkIfNeedsCollapsing() {
        guard bounds.width > 0, let font = textView.font, font.lineHeight > 0 else {
            needsCollapsing = false
            return
        }
        let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let lineHeight = font.lineHeight
        actualLineCount = max(1, Int(ceil(textSize.height / lineHeight)))
        needsCollapsing = actualLineCount > maximumNumberOfLines
        toggleButton.isHidden = !needsCollapsing
    }
    private func updateCollapsedState() {
        UIView.performWithoutAnimation {
            let title = isCollapsed ? NSLocalizedString("More", comment: "") : NSLocalizedString("Less", comment: "")
            toggleButton.setTitle(title, for: .normal)
            if isCollapsed && needsCollapsing {
                textView.textContainer.maximumNumberOfLines = maximumNumberOfLines
            } else {
                textView.textContainer.maximumNumberOfLines = 0
            }
            toggleButton.isHidden = !needsCollapsing
            textView.layoutIfNeeded()
            self.layoutIfNeeded()
            self.invalidateIntrinsicContentSize()
        }
    }
    private func initialize() {
        #if !os(tvOS)
        textView.isEditable = false
        #endif
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byTruncatingTail
        textView.backgroundColor = .clear

        textView.isSelectable = true
        textView.delegate = self
        #if !os(tvOS)
        textView.dataDetectorTypes = .link
        #endif
        configureMarkdownParser()
        addSubview(textView)
        toggleButton.addTarget(self, action: #selector(toggleCollapsed(_:)), for: .primaryActionTriggered)
        addSubview(toggleButton)
        setNeedsLayout()
    }

    private func configureMarkdownParser() {
        #if !os(tvOS)
        markdownParser.enabledElements = MarkdownManager.enabledElements
        markdownParser.header.font = MarkdownManager.Fonts.header
        markdownParser.list.font = MarkdownManager.Fonts.list
        markdownParser.bold.font = MarkdownManager.Fonts.bold
        markdownParser.italic.font = MarkdownManager.Fonts.italic
        markdownParser.quote.font = MarkdownManager.Fonts.quote
        markdownParser.header.color = MarkdownManager.Color.header
        markdownParser.bold.color =  MarkdownManager.Color.bold
        markdownParser.list.color =  MarkdownManager.Color.bold
        #endif
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        UIView.performWithoutAnimation {
            let buttonHeight = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000)).height
            textView.frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: bounds.height - buttonHeight
            )
            if previousSize?.width != bounds.width {
                checkIfNeedsCollapsing()
                updateCollapsedState()
                previousSize = bounds.size
            }
            let buttonSize = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000))
            toggleButton.frame = CGRect(
                x: bounds.width - buttonSize.width,
                y: textView.frame.maxY,
                width: buttonSize.width,
                height: buttonHeight
            )
        }
    }
    @objc private func toggleCollapsed(_ sender: UIButton) {
        isCollapsed.toggle()
        didToggleCollapse?()
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0, let font = textView.font, font.lineHeight > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }
        let lineHeight = font.lineHeight
        let buttonHeight = toggleButton.sizeThatFits(CGSize(width: 1000, height: 1000)).height
        if isCollapsed && needsCollapsing {
            let collapsedHeight = lineHeight * CGFloat(maximumNumberOfLines) + 
                             lineSpacing * CGFloat(max(0, maximumNumberOfLines - 1))
            return CGSize(width: UIView.noIntrinsicMetric, height: collapsedHeight + buttonHeight)
        } else if !needsCollapsing {
            let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: textSize.height + buttonHeight)
        } else {
            let textSize = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: textSize.height + buttonHeight)
        }
    }

    private func updateMarkdownContent() {
        #if !os(tvOS)
        let attributedString = markdownParser.parse(text)
        #else
        let attributedString: NSAttributedString
        if let nativeAttributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            attributedString = NSAttributedString(nativeAttributed)
        } else {
            attributedString = NSAttributedString(string: text)
        }
        #endif
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        mutableAttributedString.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: mutableAttributedString.length)
        )
        textView.attributedText = mutableAttributedString
        checkIfNeedsCollapsing()
        updateCollapsedState()
    }
}

extension CollapsingMarkdownView: UITextViewDelegate {
    #if !os(tvOS)
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL)
        return false 
    }
    #endif
    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
    }
}
