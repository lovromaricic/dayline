import Domain
import SwiftUI

/// "Blocks · N today" with search and category filter (spec 5.3).
struct BlocksList: View {
    @ObservedObject var vm: HomeViewModel
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(title).eyebrow()
                Spacer()
                TextField("Search tab titles", text: $vm.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused(searchFocus)
                    .padding(.horizontal, 12)
                    .frame(width: 200, height: 32)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.railFill))
                    .accessibilityLabel("Search tab titles and apps")
                    .onExitCommand { vm.search = ""; searchFocus.wrappedValue = false }
                Menu {
                    Button("All categories") { vm.categoryFilter = nil }
                    Divider()
                    ForEach(vm.report.lanes, id: \.category) { lane in
                        Button(lane.category.name) { vm.categoryFilter = lane.category }
                    }
                } label: {
                    Text(vm.categoryFilter?.name ?? "All categories")
                        .font(.system(size: 13))
                        .foregroundStyle(vm.categoryFilter == nil ? Theme.textMuted : Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.railFill))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            VStack(spacing: 0) {
                let rows = vm.visibleBlocks
                if rows.isEmpty {
                    Text(vm.isFiltering ? "No blocks match." : emptyText)
                        .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, b in
                    BlockRow(block: b, selected: vm.selection == b.id,
                             hideTopBorder: vm.selection == b.id || (i > 0 && vm.selection == rows[i - 1].id))
                        .onTapGesture { vm.select(vm.selection == b.id ? nil : b.id) }
                        .accessibilityAction { vm.select(vm.selection == b.id ? nil : b.id) }
                        .accessibilityHint(vm.selection == b.id ? "Deselects the block" : "Shows the block in the inspector")
                        .id(b.id)
                }
                if !vm.isFiltering, vm.filteredBlocks.count > HomeViewModel.collapsedCount {
                    Button(vm.showAllBlocks ? "Show fewer" : "Show all \(vm.filteredBlocks.count) blocks") {
                        vm.showAllBlocks.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var title: String {
        let n = vm.report.blocks.count
        return vm.report.isToday ? "BLOCKS · \(n) TODAY" : "BLOCKS · \(n)"
    }

    private var emptyText: String {
        vm.report.isToday ? "Blocks of a minute or more appear here as you work." : "No blocks this day."
    }
}

private struct BlockRow: View {
    var block: Block
    var selected: Bool
    var hideTopBorder: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(Fmt.range(block.start, block.end, open: block.isOpen))
                .font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textMuted)
                .frame(width: 96, alignment: .leading)
            Circle().fill(Color(hexString: block.category.color)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(block.title ?? block.appName).font(.system(size: 14)).lineLimit(1).truncationMode(.tail)
                Text(block.appName).font(.system(size: 12)).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(block.edited ? "\(block.category.name) · edited" : block.category.name)
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                .lineLimit(1).frame(width: 150, alignment: .leading)
            Text(Durations.format(block.duration)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textMuted)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color(hex: 0x7A9BFF, opacity: 0.10) : .clear))
        .overlay(alignment: .top) { Rectangle().fill(hideTopBorder ? .clear : Theme.border).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
