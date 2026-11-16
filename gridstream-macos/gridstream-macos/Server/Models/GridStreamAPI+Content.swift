import GridStreamAPI
import Vapor

// Vapor `Content` conformance for the shared wire types the routes decode or
// return. The types themselves live in GridStreamKit (`GridStreamAPI`).

nonisolated extension VideoItem: @retroactive Content {}
nonisolated extension PaginatedVideosResponse: @retroactive Content {}
nonisolated extension PlaybackStatsRequest: @retroactive Content {}
nonisolated extension PlaybackStatsDTO: @retroactive Content {}
nonisolated extension RatingRequest: @retroactive Content {}
nonisolated extension RatingDTO: @retroactive Content {}

nonisolated extension TagDTO: @retroactive Content {}
nonisolated extension TagsResponse: @retroactive Content {}
nonisolated extension CreateTagRequest: @retroactive Content {}
nonisolated extension UpdateTagRequest: @retroactive Content {}
nonisolated extension TagDeleteResponse: @retroactive Content {}
nonisolated extension ApplyTagsRequest: @retroactive Content {}
nonisolated extension VideoTagsResponse: @retroactive Content {}
nonisolated extension BulkTagApplyRequest: @retroactive Content {}
nonisolated extension BulkTagApplyResponse: @retroactive Content {}

nonisolated extension SmartListDTO: @retroactive Content {}
nonisolated extension SmartListsResponse: @retroactive Content {}
nonisolated extension CreateSmartListRequest: @retroactive Content {}
nonisolated extension UpdateSmartListRequest: @retroactive Content {}
nonisolated extension SmartListDeleteResponse: @retroactive Content {}
nonisolated extension SmartListMembershipsResponse: @retroactive Content {}

nonisolated extension SimpleListDTO: @retroactive Content {}
nonisolated extension SimpleListsResponse: @retroactive Content {}
nonisolated extension CreateSimpleListRequest: @retroactive Content {}
nonisolated extension UpdateSimpleListRequest: @retroactive Content {}
nonisolated extension AddVideosRequest: @retroactive Content {}
nonisolated extension SimpleListDeleteResponse: @retroactive Content {}

nonisolated extension TimeRangeDTO: @retroactive Content {}
nonisolated extension TimeRangeListResponse: @retroactive Content {}
nonisolated extension CreateTimeRangeRequest: @retroactive Content {}

nonisolated extension AnnotationDTO: @retroactive Content {}
nonisolated extension AnnotationListResponse: @retroactive Content {}
nonisolated extension AnnotationTimesResponse: @retroactive Content {}
nonisolated extension UpsertAnnotationRequest: @retroactive Content {}

nonisolated extension FrameCaptureDTO: @retroactive Content {}
nonisolated extension FrameCaptureListResponse: @retroactive Content {}
nonisolated extension CreateFrameCaptureRequest: @retroactive Content {}

nonisolated extension CatalogStatusDTO: @retroactive Content {}
nonisolated extension SourceDirectoryDTO: @retroactive Content {}
nonisolated extension SourceDirectoriesResponse: @retroactive Content {}
nonisolated extension AuthSessionResponse: @retroactive Content {}
nonisolated extension LoginRequest: @retroactive Content {}
