//
//  SmartListConditionRow.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

/// A single condition row in the Smart List form.
/// Shows criteria type picker, value input based on type, and AND/OR selector.
struct SmartListConditionRow: View {
    @Binding var condition: FilterCondition
    let isFirst: Bool
    let tags: [TagInfo]
    let sourceDirectories: [SourceDirectoryDTO]
    let simpleLists: [SimpleListDTO]
    let smartLists: [SmartListInfo]
    let usedCategories: Set<CriteriaCategory>
    let onRemove: () -> Void

    private var availableCategories: [CriteriaCategory] {
        let currentCategory = condition.criteriaType.category
        return CriteriaCategory.allCases.filter { category in
            category == currentCategory || !usedCategories.contains(category)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // AND/OR selector (hidden for first row)
            if !isFirst {
                logicOperatorPicker
            }

            // Main condition content
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Category picker
                    categoryPicker

                    // Value input based on criteria type
                    criteriaValueInput
                }

                Spacer()

                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove condition")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Logic Operator Picker

    private var logicOperatorPicker: some View {
        Picker("Logic", selection: $condition.logicOperator) {
            Text("AND").tag(LogicOperator.and)
            Text("OR").tag(LogicOperator.or)
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
        .accessibilityLabel("Combine with previous condition using")
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        Picker("Criteria", selection: categoryBinding) {
            ForEach(availableCategories, id: \.self) { category in
                Text(category.displayName).tag(category)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Condition type")
    }

    private var categoryBinding: Binding<CriteriaCategory> {
        Binding(
            get: { condition.criteriaType.category },
            set: { newCategory in
                if newCategory != condition.criteriaType.category {
                    condition.criteriaType = defaultCriteriaType(for: newCategory)
                }
            }
        )
    }

    // MARK: - Criteria Value Input

    @ViewBuilder
    private var criteriaValueInput: some View {
        switch condition.criteriaType {
        case .tagsInclude, .tagsExclude:
            TagCriteriaInput(
                criteriaType: $condition.criteriaType,
                tags: tags
            )

        case .ratingMin, .ratingMax:
            RatingCriteriaInput(criteriaType: $condition.criteriaType)

        case .sourceDirectory:
            SourceDirectoryCriteriaInput(
                criteriaType: $condition.criteriaType,
                directories: sourceDirectories
            )

        case .fileSizeMin, .fileSizeMax:
            FileSizeCriteriaInput(criteriaType: $condition.criteriaType)

        case .filenameContains, .filenameStartsWith, .filenameEndsWith, .filenameRegex:
            FilenameCriteriaInput(criteriaType: $condition.criteriaType)

        case .dateAddedAfter, .dateAddedBefore, .dateModifiedAfter, .dateModifiedBefore:
            DateCriteriaInput(criteriaType: $condition.criteriaType)

        case .playCountMin, .playCountMax:
            PlayCountCriteriaInput(criteriaType: $condition.criteriaType)

        case .hasAnnotations, .annotationCountMin, .annotationCountMax, .hasTextAnnotations, .annotationTextSearch:
            AnnotationCriteriaInput(criteriaType: $condition.criteriaType)

        case .hasTimeRanges:
            SegmentCriteriaInput(criteriaType: $condition.criteriaType)

        case .simpleListInclude:
            SimpleListCriteriaInput(criteriaType: $condition.criteriaType, simpleLists: simpleLists)

        case .smartListInclude:
            SmartListCriteriaInput(criteriaType: $condition.criteriaType, smartLists: smartLists)

        case .unrated, .unplayed:
            Text(condition.criteriaType.displayName)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Default Criteria Type

    private func defaultCriteriaType(for category: CriteriaCategory) -> CriteriaType {
        switch category {
        case .tags:
            return .tagsInclude(tagIds: [], tagRatings: [])
        case .rating:
            return .ratingMin(value: 3)
        case .source:
            return .sourceDirectory(id: sourceDirectories.first?.id ?? "")
        case .fileSize:
            return .fileSizeMin(megabytes: 100)
        case .filename:
            return .filenameContains(text: "")
        case .date:
            return .dateAddedAfter(date: Date().addingTimeInterval(-86400 * 30))
        case .playCount:
            return .playCountMin(value: 1)
        case .annotations:
            return .hasAnnotations(value: true)
        case .segments:
            return .hasTimeRanges(value: true)
        case .simpleList:
            return .simpleListInclude(simpleListId: UUID())
        case .smartList:
            return .smartListInclude(smartListId: UUID())
        }
    }
}

// MARK: - Simple List Criteria Input

private struct SimpleListCriteriaInput: View {
    @Binding var criteriaType: CriteriaType
    let simpleLists: [SimpleListDTO]

    private var selectedListId: UUID {
        if case .simpleListInclude(let listId) = criteriaType { return listId }
        return UUID()
    }

    var body: some View {
        Picker("Simple List", selection: listIdBinding) {
            Text("Select a list...").tag(UUID())
            ForEach(simpleLists) { list in
                Text(list.name).tag(list.id)
            }
        }
        .pickerStyle(.menu)
    }

    private var listIdBinding: Binding<UUID> {
        Binding(
            get: { selectedListId },
            set: { newId in criteriaType = .simpleListInclude(simpleListId: newId) }
        )
    }
}

// MARK: - Smart List Criteria Input

private struct SmartListCriteriaInput: View {
    @Binding var criteriaType: CriteriaType
    let smartLists: [SmartListInfo]

    private var selectedSmartListId: UUID {
        if case .smartListInclude(let smartListId) = criteriaType { return smartListId }
        return UUID()
    }

    var body: some View {
        Picker("Smart List", selection: smartListIdBinding) {
            Text("Select a smart list...").tag(UUID())
            ForEach(smartLists) { list in
                Text(list.name).tag(list.id)
            }
        }
        .pickerStyle(.menu)
    }

    private var smartListIdBinding: Binding<UUID> {
        Binding(
            get: { selectedSmartListId },
            set: { newId in criteriaType = .smartListInclude(smartListId: newId) }
        )
    }
}

// MARK: - Tag Criteria Input

private struct TagCriteriaInput: View {
    @Binding var criteriaType: CriteriaType
    let tags: [TagInfo]

    @State private var showingTagPicker = false

    private var isIncludeMode: Bool {
        if case .tagsInclude = criteriaType { return true }
        return false
    }

    private var selectedTagIds: [UUID] {
        switch criteriaType {
        case .tagsInclude(let ids, _): return ids
        case .tagsExclude(let ids): return ids
        default: return []
        }
    }

    private var currentTagRatings: [TagRatingFilter] {
        if case .tagsInclude(_, let tagRatings) = criteriaType {
            return tagRatings
        }
        return []
    }

    private var selectedTags: [TagInfo] {
        tags.filter { selectedTagIds.contains($0.id) }
    }

    /// Returns display text showing rating filter if present
    private func tagDisplayText(for tag: TagInfo) -> String? {
        guard isIncludeMode, tag.ratingEnabled,
              let rating = currentTagRatings.first(where: { $0.tagId == tag.id }),
              rating.hasRatingFilter else {
            return nil
        }
        if let min = rating.minRating, let max = rating.maxRating {
            return "\(min)-\(max)"
        } else if let min = rating.minRating {
            return "\(min)+"
        } else if let max = rating.maxRating {
            return "≤\(max)"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Include/Exclude picker
            Picker("Mode", selection: Binding(
                get: { isIncludeMode },
                set: { newValue in
                    if newValue {
                        criteriaType = .tagsInclude(tagIds: selectedTagIds, tagRatings: currentTagRatings)
                    } else {
                        criteriaType = .tagsExclude(tagIds: selectedTagIds)
                    }
                }
            )) {
                Text("Include").tag(true)
                Text("Exclude").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            // Selected tags display
            if selectedTags.isEmpty {
                Button {
                    showingTagPicker = true
                } label: {
                    Label("Select Tags", systemImage: "tag")
                        .foregroundStyle(.blue)
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(selectedTags.prefix(3)) { tag in
                        TagChip(tag: tag, ratingText: tagDisplayText(for: tag))
                    }
                    if selectedTags.count > 3 {
                        Text("+\(selectedTags.count - 3)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingTagPicker = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingTagPicker) {
            SmartListTagSelectSheet(
                tags: tags,
                selectedTagIds: Binding(
                    get: { Set(selectedTagIds) },
                    set: { newIds in
                        if isIncludeMode {
                            // Preserve existing ratings for tags that remain selected
                            let newTagIds = Array(newIds)
                            let preservedRatings = currentTagRatings.filter { newIds.contains($0.tagId) }
                            criteriaType = .tagsInclude(tagIds: newTagIds, tagRatings: preservedRatings)
                        } else {
                            criteriaType = .tagsExclude(tagIds: Array(newIds))
                        }
                    }
                ),
                tagRatings: Binding(
                    get: { currentTagRatings },
                    set: { newRatings in
                        if isIncludeMode {
                            criteriaType = .tagsInclude(tagIds: selectedTagIds, tagRatings: newRatings)
                        }
                    }
                ),
                showRatings: isIncludeMode,
                onDone: { showingTagPicker = false }
            )
        }
    }
}

private struct TagChip: View {
    let tag: TagInfo
    var ratingText: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 8, height: 8)
            Text(tag.name)
                .font(.caption)
            if let ratingText = ratingText {
                Text("(\(ratingText))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.swiftUIColor.opacity(0.2))
        .clipShape(Capsule())
    }
}

/// Sheet for selecting tags with optional per-tag rating filters for Smart Lists.
private struct SmartListTagSelectSheet: View {
    let tags: [TagInfo]
    @Binding var selectedTagIds: Set<UUID>
    @Binding var tagRatings: [TagRatingFilter]
    let showRatings: Bool
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(tags) { tag in
                    SmartListTagRow(
                        tag: tag,
                        isSelected: selectedTagIds.contains(tag.id),
                        minRating: getMinRating(for: tag.id),
                        maxRating: getMaxRating(for: tag.id),
                        showRating: showRatings,
                        onToggle: { toggleTag(tag.id) },
                        onMinRatingChange: { newMin in setMinRating(newMin, for: tag.id) },
                        onMaxRatingChange: { newMax in setMaxRating(newMax, for: tag.id) }
                    )
                }
            }
            .navigationTitle("Select Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    // MARK: - State Helpers

    private func getMinRating(for tagId: UUID) -> Int? {
        tagRatings.first { $0.tagId == tagId }?.minRating
    }

    private func getMaxRating(for tagId: UUID) -> Int? {
        tagRatings.first { $0.tagId == tagId }?.maxRating
    }

    private func toggleTag(_ tagId: UUID) {
        if selectedTagIds.contains(tagId) {
            selectedTagIds.remove(tagId)
            tagRatings.removeAll { $0.tagId == tagId }
        } else {
            selectedTagIds.insert(tagId)
        }
    }

    private func setMinRating(_ rating: Int?, for tagId: UUID) {
        let currentMax = getMaxRating(for: tagId)
        tagRatings.removeAll { $0.tagId == tagId }
        if rating != nil || currentMax != nil {
            tagRatings.append(TagRatingFilter(tagId: tagId, minRating: rating, maxRating: currentMax))
        }
    }

    private func setMaxRating(_ rating: Int?, for tagId: UUID) {
        let currentMin = getMinRating(for: tagId)
        tagRatings.removeAll { $0.tagId == tagId }
        if currentMin != nil || rating != nil {
            tagRatings.append(TagRatingFilter(tagId: tagId, minRating: currentMin, maxRating: rating))
        }
    }
}

/// Individual row in the Smart List tag selector.
private struct SmartListTagRow: View {
    let tag: TagInfo
    let isSelected: Bool
    let minRating: Int?
    let maxRating: Int?
    let showRating: Bool
    let onToggle: () -> Void
    let onMinRatingChange: (Int?) -> Void
    let onMaxRatingChange: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row with tag selection
            Button(action: onToggle) {
                HStack {
                    Circle()
                        .fill(tag.swiftUIColor)
                        .frame(width: 16, height: 16)

                    Text(tag.name)
                        .foregroundStyle(.primary)

                    if tag.ratingEnabled {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)

            // Rating filter controls (only show when selected, showRating=true, and tag has ratingEnabled)
            if isSelected && showRating && tag.ratingEnabled {
                SmartListTagRatingControls(
                    minRating: minRating,
                    maxRating: maxRating,
                    onMinRatingChange: onMinRatingChange,
                    onMaxRatingChange: onMaxRatingChange
                )
                .padding(.top, 12)
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact rating filter controls for Smart List per-tag ratings.
private struct SmartListTagRatingControls: View {
    let minRating: Int?
    let maxRating: Int?
    let onMinRatingChange: (Int?) -> Void
    let onMaxRatingChange: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rating Filter")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Min rating picker
                HStack(spacing: 4) {
                    Text("Min:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { minRating ?? -1 },
                        set: { onMinRatingChange($0 == -1 ? nil : $0) }
                    )) {
                        Text("Any").tag(-1)
                        ForEach(0...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                // Max rating picker
                HStack(spacing: 4) {
                    Text("Max:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { maxRating ?? -1 },
                        set: { onMaxRatingChange($0 == -1 ? nil : $0) }
                    )) {
                        Text("Any").tag(-1)
                        ForEach(0...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - Rating Criteria Input

private struct RatingCriteriaInput: View {
    @Binding var criteriaType: CriteriaType

    private var isMinMode: Bool {
        if case .ratingMin = criteriaType { return true }
        return false
    }

    private var currentValue: Int {
        switch criteriaType {
        case .ratingMin(let value): return value
        case .ratingMax(let value): return value
        default: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Min/Max picker
            Picker("Type", selection: Binding(
                get: { isMinMode },
                set: { newValue in
                    if newValue {
                        criteriaType = .ratingMin(value: currentValue)
                    } else {
                        criteriaType = .ratingMax(value: currentValue)
                    }
                }
            )) {
                Text("At least").tag(true)
                Text("At most").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            // Rating stepper with hearts (0-10 scale)
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        if isMinMode {
                            criteriaType = .ratingMin(value: value)
                        } else {
                            criteriaType = .ratingMax(value: value)
                        }
                    } label: {
                        Image(systemName: value <= currentValue ? "heart.fill" : "heart")
                            .foregroundStyle(value <= currentValue ? .red : .gray)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(currentValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
        }
    }
}

// MARK: - Source Directory Criteria Input

private struct SourceDirectoryCriteriaInput: View {
    @Binding var criteriaType: CriteriaType
    let directories: [SourceDirectoryDTO]

    private var selectedId: String {
        if case .sourceDirectory(let id) = criteriaType {
            return id
        }
        return ""
    }

    var body: some View {
        if directories.isEmpty {
            Text("No source directories available")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Directory", selection: Binding(
                get: { selectedId },
                set: { newId in
                    criteriaType = .sourceDirectory(id: newId)
                }
            )) {
                ForEach(directories) { dir in
                    Text(dir.name).tag(dir.id)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - File Size Criteria Input

private struct FileSizeCriteriaInput: View {
    @Binding var criteriaType: CriteriaType

    private var isMinMode: Bool {
        if case .fileSizeMin = criteriaType { return true }
        return false
    }

    private var currentValue: Double {
        switch criteriaType {
        case .fileSizeMin(let mb): return mb
        case .fileSizeMax(let mb): return mb
        default: return 0
        }
    }

    @State private var sizeText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Min/Max picker
            Picker("Type", selection: Binding(
                get: { isMinMode },
                set: { newValue in
                    if newValue {
                        criteriaType = .fileSizeMin(megabytes: currentValue)
                    } else {
                        criteriaType = .fileSizeMax(megabytes: currentValue)
                    }
                }
            )) {
                Text("At least").tag(true)
                Text("At most").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            // Size input
            HStack {
                TextField("Size", text: Binding(
                    get: { currentValue > 0 ? String(format: "%.0f", currentValue) : "" },
                    set: { newValue in
                        if let mb = Double(newValue) {
                            if isMinMode {
                                criteriaType = .fileSizeMin(megabytes: mb)
                            } else {
                                criteriaType = .fileSizeMax(megabytes: mb)
                            }
                        }
                    }
                ))
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)

                Text("MB")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Filename Criteria Input

private struct FilenameCriteriaInput: View {
    @Binding var criteriaType: CriteriaType

    private enum MatchType: String, CaseIterable {
        case contains = "Contains"
        case startsWith = "Starts with"
        case endsWith = "Ends with"
        case regex = "Regex"

        var title: LocalizedStringResource {
            switch self {
            case .contains: return "Contains"
            case .startsWith: return "Starts with"
            case .endsWith: return "Ends with"
            case .regex: return "Regex"
            }
        }
    }

    private var currentMatchType: MatchType {
        switch criteriaType {
        case .filenameContains: return .contains
        case .filenameStartsWith: return .startsWith
        case .filenameEndsWith: return .endsWith
        case .filenameRegex: return .regex
        default: return .contains
        }
    }

    private var currentText: String {
        switch criteriaType {
        case .filenameContains(let text): return text
        case .filenameStartsWith(let text): return text
        case .filenameEndsWith(let text): return text
        case .filenameRegex(let pattern): return pattern
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Match type picker
            Picker("Match Type", selection: Binding(
                get: { currentMatchType },
                set: { newType in
                    switch newType {
                    case .contains:
                        criteriaType = .filenameContains(text: currentText)
                    case .startsWith:
                        criteriaType = .filenameStartsWith(text: currentText)
                    case .endsWith:
                        criteriaType = .filenameEndsWith(text: currentText)
                    case .regex:
                        criteriaType = .filenameRegex(pattern: currentText)
                    }
                }
            )) {
                ForEach(MatchType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.menu)

            // Text input
            TextField("Pattern", text: Binding(
                get: { currentText },
                set: { newText in
                    switch currentMatchType {
                    case .contains:
                        criteriaType = .filenameContains(text: newText)
                    case .startsWith:
                        criteriaType = .filenameStartsWith(text: newText)
                    case .endsWith:
                        criteriaType = .filenameEndsWith(text: newText)
                    case .regex:
                        criteriaType = .filenameRegex(pattern: newText)
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
    }
}

// MARK: - Date Criteria Input

private struct DateCriteriaInput: View {
    @Binding var criteriaType: CriteriaType

    private enum DateType: String, CaseIterable {
        case addedAfter = "Added after"
        case addedBefore = "Added before"
        case modifiedAfter = "Modified after"
        case modifiedBefore = "Modified before"

        var title: LocalizedStringResource {
            switch self {
            case .addedAfter: return "Added after"
            case .addedBefore: return "Added before"
            case .modifiedAfter: return "Modified after"
            case .modifiedBefore: return "Modified before"
            }
        }
    }

    private var currentDateType: DateType {
        switch criteriaType {
        case .dateAddedAfter: return .addedAfter
        case .dateAddedBefore: return .addedBefore
        case .dateModifiedAfter: return .modifiedAfter
        case .dateModifiedBefore: return .modifiedBefore
        default: return .addedAfter
        }
    }

    private var currentDate: Date {
        switch criteriaType {
        case .dateAddedAfter(let date): return date
        case .dateAddedBefore(let date): return date
        case .dateModifiedAfter(let date): return date
        case .dateModifiedBefore(let date): return date
        default: return Date()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date type picker
            Picker("Type", selection: Binding(
                get: { currentDateType },
                set: { newType in
                    switch newType {
                    case .addedAfter:
                        criteriaType = .dateAddedAfter(date: currentDate)
                    case .addedBefore:
                        criteriaType = .dateAddedBefore(date: currentDate)
                    case .modifiedAfter:
                        criteriaType = .dateModifiedAfter(date: currentDate)
                    case .modifiedBefore:
                        criteriaType = .dateModifiedBefore(date: currentDate)
                    }
                }
            )) {
                ForEach(DateType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.menu)

            // Date picker
            DatePicker(
                "Date",
                selection: Binding(
                    get: { currentDate },
                    set: { newDate in
                        switch currentDateType {
                        case .addedAfter:
                            criteriaType = .dateAddedAfter(date: newDate)
                        case .addedBefore:
                            criteriaType = .dateAddedBefore(date: newDate)
                        case .modifiedAfter:
                            criteriaType = .dateModifiedAfter(date: newDate)
                        case .modifiedBefore:
                            criteriaType = .dateModifiedBefore(date: newDate)
                        }
                    }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
        }
    }
}

// MARK: - Play Count Criteria Input

private struct PlayCountCriteriaInput: View {
    @Binding var criteriaType: CriteriaType

    private var isMinMode: Bool {
        if case .playCountMin = criteriaType { return true }
        return false
    }

    private var currentValue: Int {
        switch criteriaType {
        case .playCountMin(let value): return value
        case .playCountMax(let value): return value
        default: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Min/Max picker
            Picker("Type", selection: Binding(
                get: { isMinMode },
                set: { newValue in
                    if newValue {
                        criteriaType = .playCountMin(value: currentValue)
                    } else {
                        criteriaType = .playCountMax(value: currentValue)
                    }
                }
            )) {
                Text("At least").tag(true)
                Text("At most").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            // Count stepper
            Stepper(
                value: Binding(
                    get: { currentValue },
                    set: { newValue in
                        if isMinMode {
                            criteriaType = .playCountMin(value: newValue)
                        } else {
                            criteriaType = .playCountMax(value: newValue)
                        }
                    }
                ),
                in: 0...1000
            ) {
                Text("\(currentValue) plays")
            }
        }
    }
}

// MARK: - Annotation Criteria Input

private struct AnnotationCriteriaInput: View {
    @Binding var criteriaType: CriteriaType

    private enum AnnotationMode: String, CaseIterable {
        case hasAnnotations = "Has Annotations"
        case countMin = "Min Count"
        case countMax = "Max Count"
        case hasTextAnnotations = "Has Text Annotation"
        case textSearch = "Text Contains/Search"

        var title: LocalizedStringResource {
            switch self {
            case .hasAnnotations: return "Has Annotations"
            case .countMin: return "Min Count"
            case .countMax: return "Max Count"
            case .hasTextAnnotations: return "Has Text Annotation"
            case .textSearch: return "Text Contains/Search"
            }
        }
    }

    private var currentMode: AnnotationMode {
        switch criteriaType {
        case .hasAnnotations: return .hasAnnotations
        case .annotationCountMin: return .countMin
        case .annotationCountMax: return .countMax
        case .hasTextAnnotations: return .hasTextAnnotations
        case .annotationTextSearch: return .textSearch
        default: return .hasAnnotations
        }
    }

    private var boolValue: Bool {
        switch criteriaType {
        case .hasAnnotations(let value), .hasTextAnnotations(let value):
            return value
        default:
            return true
        }
    }

    private var textValue: String {
        if case .annotationTextSearch(let text) = criteriaType { return text }
        return ""
    }

    private var nextTextValue: String {
        textValue.isEmpty ? "" : textValue
    }

    private var nextCountValue: Int {
        countValue
    }

    private var nextBoolValue: Bool {
        return true
    }

    private var countValue: Int {
        switch criteriaType {
        case .annotationCountMin(let value): return value
        case .annotationCountMax(let value): return value
        default: return 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode picker
            Picker("Type", selection: Binding(
                get: { currentMode },
                set: { newMode in
                    switch newMode {
                    case .hasAnnotations:
                        criteriaType = .hasAnnotations(value: true)
                    case .countMin:
                        criteriaType = .annotationCountMin(value: nextCountValue)
                    case .countMax:
                        criteriaType = .annotationCountMax(value: nextCountValue)
                    case .hasTextAnnotations:
                        criteriaType = .hasTextAnnotations(value: nextBoolValue)
                    case .textSearch:
                        criteriaType = .annotationTextSearch(text: nextTextValue)
                    }
                }
            )) {
                ForEach(AnnotationMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            // Value input based on mode
            switch currentMode {
            case .hasAnnotations:
                Picker("Value", selection: Binding(
                    get: { boolValue },
                    set: { criteriaType = .hasAnnotations(value: $0) }
                )) {
                    Text("Yes").tag(true)
                    Text("No").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

            case .hasTextAnnotations:
                Picker("Value", selection: Binding(
                    get: { boolValue },
                    set: { criteriaType = .hasTextAnnotations(value: $0) }
                )) {
                    Text("Yes").tag(true)
                    Text("No").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

            case .textSearch:
                TextField(
                    "Annotation text",
                    text: Binding(
                        get: { textValue },
                        set: { criteriaType = .annotationTextSearch(text: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)

            case .countMin, .countMax:
                Stepper(
                    value: Binding(
                        get: { countValue },
                        set: { newValue in
                            if currentMode == .countMin {
                                criteriaType = .annotationCountMin(value: newValue)
                            } else {
                                criteriaType = .annotationCountMax(value: newValue)
                            }
                        }
                    ),
                    in: 0...1000
                ) {
                    Text("\(countValue) annotations")
                }
            }
        }
    }
}

// MARK: - Segment Criteria Input

private struct SegmentCriteriaInput: View {
    @Binding var criteriaType: CriteriaType

    private var value: Bool {
        if case .hasTimeRanges(let value) = criteriaType { return value }
        return true
    }

    var body: some View {
        Picker("Value", selection: Binding(
            get: { value },
            set: { criteriaType = .hasTimeRanges(value: $0) }
        )) {
            Text("Yes").tag(true)
            Text("No").tag(false)
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
    }
}

// MARK: - Previews

#Preview("Condition Row - Tags") {
    struct PreviewWrapper: View {
        @State private var condition = FilterCondition(
            criteriaType: .tagsInclude(tagIds: [], tagRatings: []),
            logicOperator: .and
        )

        var body: some View {
            Form {
                SmartListConditionRow(
                    condition: $condition,
                    isFirst: true,
                    tags: [
                        TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false),
                        TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true)
                    ],
                    sourceDirectories: [],
                    simpleLists: [],
                    smartLists: [],
                    usedCategories: [],
                    onRemove: {}
                )
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Condition Row - Rating") {
    struct PreviewWrapper: View {
        @State private var condition = FilterCondition(
            criteriaType: .ratingMin(value: 3),
            logicOperator: .or
        )

        var body: some View {
            Form {
                SmartListConditionRow(
                    condition: $condition,
                    isFirst: false,
                    tags: [],
                    sourceDirectories: [],
                    simpleLists: [],
                    smartLists: [],
                    usedCategories: [.tags],
                    onRemove: {}
                )
            }
        }
    }

    return PreviewWrapper()
}
