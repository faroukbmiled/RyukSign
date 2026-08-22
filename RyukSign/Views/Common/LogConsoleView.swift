//
//  LogConsoleView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleExtensions

// MARK: - Representable
// A SwiftUI ForEach re-diffs every row per append, which starves the presenting sheet's
// animations once the signing log starts streaming.
struct LogConsoleView: UIViewRepresentable {
	let entries: [LogEntry]
	var showCategory = false
	var onRefresh: (() -> Void)?

	func makeUIView(context: Context) -> UITableView {
		let table = UITableView(frame: .zero, style: .plain)
		table.dataSource = context.coordinator
		table.delegate = context.coordinator
		table.register(LogRowCell.self, forCellReuseIdentifier: LogRowCell.reuseIdentifier)
		table.backgroundColor = .clear
		table.separatorStyle = .none
		table.allowsSelection = false
		table.rowHeight = UITableView.automaticDimension
		table.estimatedRowHeight = 40
		table.isPrefetchingEnabled = false

		if onRefresh != nil {
			let control = UIRefreshControl()
			control.addTarget(context.coordinator, action: #selector(Coordinator.refresh), for: .valueChanged)
			table.refreshControl = control
		}

		return table
	}

	func updateUIView(_ table: UITableView, context: Context) {
		context.coordinator.onRefresh = onRefresh
		context.coordinator.apply(entries, showCategory: showCategory, to: table)
	}

	func makeCoordinator() -> Coordinator { Coordinator() }
}

// MARK: - Coordinator
extension LogConsoleView {
	final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
		var onRefresh: (() -> Void)?

		private var _entries: [LogEntry] = []
		private var _showCategory = false

		func apply(_ entries: [LogEntry], showCategory: Bool, to table: UITableView) {
			table.refreshControl?.endRefreshing()

			guard
				entries.count != _entries.count
					|| entries.first?.id != _entries.first?.id
					|| showCategory != _showCategory
			else { return }

			let anchor = _anchor(in: table)
			_entries = entries
			_showCategory = showCategory
			table.reloadData()

			guard let anchor, let row = entries.firstIndex(where: { $0.id == anchor.id }) else { return }
			table.layoutIfNeeded()
			let rect = table.rectForRow(at: IndexPath(row: row, section: 0))
			table.contentOffset.y = rect.minY - anchor.distanceFromTop
		}

		// Newest lines are prepended, so a reader in the backlog has to be pinned or the list
		// walks out from under them.
		private func _anchor(in table: UITableView) -> (id: UUID, distanceFromTop: CGFloat)? {
			guard
				table.contentOffset.y > -table.adjustedContentInset.top + 1,
				let indexPath = table.indexPathsForVisibleRows?.first,
				let entry = _entries[safe: indexPath.row]
			else { return nil }

			return (entry.id, table.rectForRow(at: indexPath).minY - table.contentOffset.y)
		}

		@objc func refresh() { onRefresh?() }

		func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
			_entries.count
		}

		func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
			let cell = tableView.dequeueReusableCell(withIdentifier: LogRowCell.reuseIdentifier, for: indexPath)
			if let cell = cell as? LogRowCell, let entry = _entries[safe: indexPath.row] {
				cell.configure(with: entry, showCategory: _showCategory)
			}
			return cell
		}

		func tableView(
			_ tableView: UITableView,
			contextMenuConfigurationForRowAt indexPath: IndexPath,
			point: CGPoint
		) -> UIContextMenuConfiguration? {
			guard let entry = _entries[safe: indexPath.row] else { return nil }

			return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
				UIMenu(children: [
					UIAction(title: .localized("Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
						UIPasteboard.general.string = entry.message
					}
				])
			}
		}
	}
}

// MARK: - Cell
private final class LogRowCell: UITableViewCell {
	static let reuseIdentifier = "LogRow"

	private let _bar = UIView()
	private let _time = UILabel()
	private let _category = PillLabel()
	private let _message = UILabel()
	private let _meta = UIStackView()
	private var _leading: NSLayoutConstraint!

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)

		backgroundColor = .clear
		selectionStyle = .none

		_bar.layer.cornerRadius = 1.25
		_bar.setContentHuggingPriority(.required, for: .horizontal)

		let metaFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
		_time.font = metaFont
		_time.textColor = .tertiaryLabel
		_category.font = metaFont
		_category.layer.cornerRadius = 7
		_category.clipsToBounds = true

		_message.font = UIFontMetrics(forTextStyle: .footnote)
			.scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
		_message.adjustsFontForContentSizeCategory = true
		_message.numberOfLines = 0

		_meta.axis = .horizontal
		_meta.spacing = 6
		_meta.alignment = .center
		[_time, _category, UIView()].forEach(_meta.addArrangedSubview)

		let column = UIStackView(arrangedSubviews: [_meta, _message])
		column.axis = .vertical
		column.spacing = 3

		let row = UIStackView(arrangedSubviews: [_bar, column])
		row.axis = .horizontal
		row.spacing = 8
		row.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(row)

		_leading = row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
		NSLayoutConstraint.activate([
			_leading,
			row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
			row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
			_bar.widthAnchor.constraint(equalToConstant: 2.5)
		])
	}

	required init?(coder: NSCoder) { fatalError() }

	func configure(with entry: LogEntry, showCategory: Bool) {
		_bar.backgroundColor = entry.kind.tint.withAlphaComponent(entry.kind == .info ? 0.4 : 1)
		_message.text = entry.message
		_message.textColor = entry.kind.textColor
		_leading.constant = entry.kind == .detail ? 24 : 16

		_time.text = entry.date.map(LogFormat.string)
		_time.isHidden = entry.date == nil

		if showCategory, let category = entry.category {
			let color = LogFormat.color(forCategory: category)
			_category.text = category.uppercased()
			_category.textColor = color
			_category.backgroundColor = color.withAlphaComponent(0.18)
			_category.isHidden = false
		} else {
			_category.isHidden = true
		}

		_meta.isHidden = entry.kind == .detail || (_time.isHidden && _category.isHidden)
	}
}

// MARK: - Pill
private final class PillLabel: UILabel {
	private static let _insets = UIEdgeInsets(top: 1.5, left: 5, bottom: 1.5, right: 5)

	override func drawText(in rect: CGRect) {
		super.drawText(in: rect.inset(by: Self._insets))
	}

	override var intrinsicContentSize: CGSize {
		let size = super.intrinsicContentSize
		return CGSize(
			width: size.width + Self._insets.left + Self._insets.right,
			height: size.height + Self._insets.top + Self._insets.bottom
		)
	}
}
