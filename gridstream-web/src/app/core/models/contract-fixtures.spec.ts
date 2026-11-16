import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { firstValueFrom } from 'rxjs';
import { VideoService } from '../services/video.service';
import { TagService } from '../services/tag.service';
import { SmartListService } from '../services/smart-list.service';
import { SimpleListService } from '../services/simple-list.service';
import { AnnotationService } from '../services/annotation.service';
import { TimeRangeService } from '../services/time-range.service';
import { FrameCaptureService } from '../services/frame-capture.service';
import { AuthService } from '../services/auth.service';
import { parseCriteria, toCriteria } from '../../shared/criteria/criteria';
import video from '../../../../../contracts/fixtures/video.json';
import videosPage from '../../../../../contracts/fixtures/videos-page.json';
import tag from '../../../../../contracts/fixtures/tag.json';
import tags from '../../../../../contracts/fixtures/tags.json';
import tagCreateRequest from '../../../../../contracts/fixtures/tag-create-request.json';
import tagUpdateRequest from '../../../../../contracts/fixtures/tag-update-request.json';
import smartList from '../../../../../contracts/fixtures/smart-list.json';
import smartLists from '../../../../../contracts/fixtures/smart-lists.json';
import smartListCreateRequest from '../../../../../contracts/fixtures/smart-list-create-request.json';
import smartListMemberships from '../../../../../contracts/fixtures/smart-list-memberships.json';
import simpleList from '../../../../../contracts/fixtures/simple-list.json';
import simpleLists from '../../../../../contracts/fixtures/simple-lists.json';
import simpleListUpdateRequest from '../../../../../contracts/fixtures/simple-list-update-request.json';
import simpleListVideosRequest from '../../../../../contracts/fixtures/simple-list-videos-request.json';
import annotation from '../../../../../contracts/fixtures/annotation.json';
import annotations from '../../../../../contracts/fixtures/annotations.json';
import annotationUpsertRequest from '../../../../../contracts/fixtures/annotation-upsert-request.json';
import timeRanges from '../../../../../contracts/fixtures/time-ranges.json';
import capture from '../../../../../contracts/fixtures/capture.json';
import captures from '../../../../../contracts/fixtures/captures.json';
import captureCreateRequest from '../../../../../contracts/fixtures/capture-create-request.json';
import authSession from '../../../../../contracts/fixtures/auth-session.json';
import smartListCriteria from '../../../../../contracts/fixtures/smart-list-criteria.json';

describe('canonical Swift and Angular contract fixtures', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('reads the canonical video page and preserves stable file IDs and versioned thumbnails', async () => {
    const service = TestBed.inject(VideoService);
    const result = firstValueFrom(service.getVideos({ limit: '100', offset: '0' }));
    http.expectOne('/api/v1/videos?limit=100&offset=0').flush(videosPage);
    const page = await result;
    expect(page.videos[0]).toEqual(video);
    expect(page.total).toBe(videosPage.total);
    expect(service.thumbnailUrl(page.videos[0])).toBe(video.thumbnailUrl);
    expect(service.streamUrl(page.videos[0].fileId)).toBe('/api/v1/videos/' + video.fileId + '/stream');
    const single = firstValueFrom(service.getVideoByFileId(video.fileId));
    http.expectOne('/api/v1/videos/by-file-id/' + video.fileId).flush(video);
    expect(await single).toEqual(video);
  });

  it('reads tags and sends the canonical create and partial update bodies', async () => {
    const service = TestBed.inject(TagService);
    const listed = firstValueFrom(service.getTags());
    http.expectOne('/api/v1/tags').flush(tags);
    expect(await listed).toEqual([tag]);
    const created = firstValueFrom(service.createTag(tagCreateRequest));
    const create = http.expectOne('/api/v1/tags');
    expect(create.request.method).toBe('POST');
    expect(create.request.body).toEqual(tagCreateRequest);
    create.flush(tag);
    expect(await created).toEqual(tag);
    const updated = firstValueFrom(service.updateTag(tag.id, tagUpdateRequest));
    const update = http.expectOne('/api/v1/tags/' + tag.id);
    expect(update.request.method).toBe('PUT');
    expect(update.request.body).toEqual(tagUpdateRequest);
    update.flush(tag);
    await updated;
  });

  it('reads smart lists and memberships and preserves encoded criteria when creating', async () => {
    const service = TestBed.inject(SmartListService);
    const listed = firstValueFrom(service.getSmartLists());
    http.expectOne('/api/v1/smart-lists').flush(smartLists);
    expect(await listed).toEqual([smartList]);
    const memberships = firstValueFrom(service.getSmartListMemberships());
    http.expectOne('/api/v1/smart-lists/memberships').flush(smartListMemberships);
    expect(await memberships).toEqual(smartListMemberships.memberships);
    const created = firstValueFrom(service.createSmartList(smartListCreateRequest.name, smartListCreateRequest.criteria));
    const request = http.expectOne('/api/v1/smart-lists');
    expect(request.request.body).toEqual(smartListCreateRequest);
    request.flush(smartList);
    expect(await created).toEqual(smartList);
    expect(toCriteria(parseCriteria(smartList.criteria))).toEqual(JSON.parse(smartList.criteria));
  });

  it('reads simple lists and sends canonical sort orders and stable video IDs', async () => {
    const service = TestBed.inject(SimpleListService);
    const listed = firstValueFrom(service.getSimpleLists());
    http.expectOne('/api/v1/simple-lists').flush(simpleLists);
    expect(await listed).toEqual([simpleList]);
    const updated = firstValueFrom(service.updateSimpleList(simpleList.id, simpleListUpdateRequest.name, simpleListUpdateRequest.sortOrder));
    const update = http.expectOne('/api/v1/simple-lists/' + simpleList.id);
    expect(update.request.body).toEqual(simpleListUpdateRequest);
    update.flush(simpleList);
    expect(await updated).toEqual(simpleList);
    const added = firstValueFrom(service.addVideos(simpleList.id, simpleListVideosRequest.videoIds));
    const add = http.expectOne('/api/v1/simple-lists/' + simpleList.id + '/videos');
    expect(add.request.body).toEqual(simpleListVideosRequest);
    add.flush(null);
    await added;
  });

  it('reads annotations and sends fractional frame keys, drawings and explicit null text unchanged', async () => {
    const service = TestBed.inject(AnnotationService);
    const listed = firstValueFrom(service.getAnnotations(video.fileId));
    http.expectOne('/api/v1/videos/' + video.fileId + '/annotations').flush(annotations);
    expect((await listed).annotations).toEqual([annotation]);
    const saved = firstValueFrom(service.upsertAnnotation(video.fileId, annotationUpsertRequest));
    const request = http.expectOne('/api/v1/videos/' + video.fileId + '/annotations');
    expect(request.request.method).toBe('PUT');
    expect(request.request.body).toEqual(annotationUpsertRequest);
    request.flush(annotation);
    expect(await saved).toEqual(annotation);
  });

  it('reads time ranges and captures and sends the canonical capture timestamp', async () => {
    const ranges = firstValueFrom(TestBed.inject(TimeRangeService).getTimeRanges(video.fileId));
    http.expectOne('/api/v1/videos/' + video.fileId + '/time-ranges').flush(timeRanges);
    expect((await ranges).timeRanges[0].videoFileId).toBe(video.fileId);
    const service = TestBed.inject(FrameCaptureService);
    const listed = firstValueFrom(service.getAllCaptures({}));
    http.expectOne('/api/v1/captures').flush(captures);
    expect((await listed).captures).toEqual([capture]);
    const created = firstValueFrom(service.createCapture(video.fileId, captureCreateRequest.timestamp));
    const request = http.expectOne('/api/v1/videos/' + video.fileId + '/captures');
    expect(request.request.body).toEqual(captureCreateRequest);
    request.flush(capture);
    expect(await created).toEqual(capture);
  });

  it('accepts the shared session response and uses cookie credentials', async () => {
    const service = TestBed.inject(AuthService);
    const initialized = service.initialize();
    const request = http.expectOne('/api/v1/auth/session');
    expect(request.request.withCredentials).toBe(true);
    request.flush(authSession);
    await initialized;
    expect(service.isAuthenticated()).toBe(authSession.authenticated);
    expect(service.authEnabled()).toBe(authSession.authEnabled);
  });

  it('reads all 27 canonical smart-list condition variants without dropping fields', () => {
    const drafts = parseCriteria(JSON.stringify(smartListCriteria));
    expect(drafts).toHaveLength(27);
    expect(drafts.map((draft) => draft.type)).toEqual(smartListCriteria.conditions.map((condition) => condition.criteriaType.type));
    expect(drafts.map((draft) => draft.id)).toEqual(smartListCriteria.conditions.map((condition) => condition.id));
    const encoded = toCriteria(drafts)!;
    for (const [index, condition] of encoded.conditions.entries()) {
      const original = smartListCriteria.conditions[index];
      if ('date' in condition.criteriaType) {
        const originalType = original.criteriaType;
        expect('date' in originalType).toBe(true);
        expect(Number.isNaN(Date.parse(condition.criteriaType.date))).toBe(false);
        expect(drafts[index].date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      } else {
        expect(condition.criteriaType).toEqual(original.criteriaType);
      }
      expect(condition.logicOperator).toBe(original.logicOperator);
    }
  });
});
