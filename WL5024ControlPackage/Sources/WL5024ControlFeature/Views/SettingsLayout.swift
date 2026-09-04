import SwiftUI

enum DetailLayoutMetrics {
    static let maximumPageWidth: CGFloat = 760
    static let horizontalPageMargin: CGFloat = 24
    static let verticalPageMargin: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let cardInset: CGFloat = 12
    static let rowVerticalInset: CGFloat = 12
    static let labelMinimumWidth: CGFloat = 220
    static let columnGap: CGFloat = 24
    static let controlWidth: CGFloat = 300
    static let wideControlWidth: CGFloat = 340
    static let stackedGap: CGFloat = 12
    static let pickerWidth: CGFloat = 220
    static let sliderValueWidth: CGFloat = 32
}

struct DetailPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DetailLayoutMetrics.sectionSpacing) {
                content
            }
            .padding(.horizontal, DetailLayoutMetrics.horizontalPageMargin)
            .padding(.vertical, DetailLayoutMetrics.verticalPageMargin)
            .frame(maxWidth: DetailLayoutMetrics.maximumPageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

struct SettingsRowLayout: Layout {
    let controlWidth: CGFloat

    init(controlWidth: CGFloat = DetailLayoutMetrics.controlWidth) {
        self.controlWidth = controlWidth
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let availableWidth = proposal.width ?? regularThreshold
        if availableWidth >= regularThreshold {
            let labelWidth = availableWidth - controlWidth - DetailLayoutMetrics.columnGap
            let labelSize = subviews[0].sizeThatFits(.init(width: labelWidth, height: nil))
            let controlSize = subviews[1].sizeThatFits(.init(width: controlWidth, height: nil))
            return CGSize(width: availableWidth, height: max(labelSize.height, controlSize.height))
        }

        let labelSize = subviews[0].sizeThatFits(.init(width: availableWidth, height: nil))
        let compactControlWidth = min(controlWidth, availableWidth)
        let controlSize = subviews[1].sizeThatFits(.init(width: compactControlWidth, height: nil))
        return CGSize(
            width: availableWidth,
            height: labelSize.height + DetailLayoutMetrics.stackedGap + controlSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        if bounds.width >= regularThreshold {
            let labelWidth = bounds.width - controlWidth - DetailLayoutMetrics.columnGap
            let labelSize = subviews[0].sizeThatFits(.init(width: labelWidth, height: nil))
            let controlSize = subviews[1].sizeThatFits(.init(width: controlWidth, height: nil))
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + (bounds.height - labelSize.height) / 2),
                proposal: .init(width: labelWidth, height: labelSize.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.maxX - controlWidth, y: bounds.minY + (bounds.height - controlSize.height) / 2),
                proposal: .init(width: controlWidth, height: controlSize.height)
            )
        } else {
            let labelSize = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil))
            let compactControlWidth = min(controlWidth, bounds.width)
            let controlSize = subviews[1].sizeThatFits(.init(width: compactControlWidth, height: nil))
            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: bounds.width, height: labelSize.height)
            )
            subviews[1].place(
                at: CGPoint(
                    x: bounds.maxX - compactControlWidth,
                    y: bounds.minY + labelSize.height + DetailLayoutMetrics.stackedGap
                ),
                proposal: .init(width: compactControlWidth, height: controlSize.height)
            )
        }
    }

    private var regularThreshold: CGFloat {
        DetailLayoutMetrics.labelMinimumWidth + DetailLayoutMetrics.columnGap + controlWidth
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            content
                .padding(DetailLayoutMetrics.cardInset)
        }
    }
}
