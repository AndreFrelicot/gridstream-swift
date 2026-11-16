import { signal } from '@angular/core';
import { of, Subject, throwError } from 'rxjs';
import {
  AnnotationInfo,
  AnnotationListResponse,
  UpsertAnnotationRequest,
} from '../../core/models/annotation.model';
import { AnnotationEditor } from './annotation-editor';

function annotation(patch: Partial<AnnotationInfo> = {}): AnnotationInfo {
  return {
    id: 'annotation-1',
    videoFileId: 'video-1',
    frameTime: 1,
    frameRate: 24,
    strokesJSON: '[]',
    text: 'Saved text',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...patch,
  };
}

function setup(initial: AnnotationInfo[] = []) {
  const time = signal(1);
  const service = {
    getAnnotations: vi.fn(() => of({ annotations: initial, total: initial.length })),
    upsertAnnotation: vi.fn((_fileId: string, request: UpsertAnnotationRequest) =>
      of(annotation(request)),
    ),
    deleteAnnotation: vi.fn(() => of(undefined)),
  };
  const editor = new AnnotationEditor(service, () => 'video-1', time);
  editor.loadAnnotations();
  return { editor, service, time };
}

describe('AnnotationEditor', () => {
  it('preserves strokes and the existing frame key when saving text', () => {
    const strokesJSON = '[{"color":"#FF0000","width":2,"opacity":1,"points":[]}]';
    const { editor, service, time } = setup([annotation({ strokesJSON })]);
    time.set(1.01);
    editor.onTextDraftInput('Edited text');
    editor.saveTextAnnotation();
    expect(service.upsertAnnotation).toHaveBeenCalledWith('video-1', {
      frameTime: 1,
      frameRate: 24,
      strokesJSON,
      text: 'Edited text',
    });
    expect(editor.currentFrameText()).toBe('Edited text');
    expect(editor.isSavingText()).toBe(false);
  });

  it('deletes an empty text-only annotation', () => {
    const { editor, service } = setup([annotation()]);
    editor.clearTextAnnotation();
    editor.saveTextAnnotation();
    expect(service.deleteAnnotation).toHaveBeenCalledWith('video-1', 'annotation-1');
    expect(service.upsertAnnotation).not.toHaveBeenCalled();
    expect(editor.annotationTimes()).toEqual([]);
  });

  it('clears text without deleting drawings', () => {
    const strokesJSON = '[{"points":[]}]';
    const { editor, service } = setup([annotation({ strokesJSON })]);
    editor.clearTextAnnotation();
    editor.saveTextAnnotation();
    expect(service.deleteAnnotation).not.toHaveBeenCalled();
    expect(service.upsertAnnotation).toHaveBeenCalledWith('video-1', {
      frameTime: 1,
      frameRate: 24,
      strokesJSON,
      text: null,
    });
  });

  it('does not overwrite an unsaved draft when playback moves', () => {
    const { editor, time } = setup([annotation()]);
    editor.onTextDraftInput('Unsaved text');
    time.set(2);
    editor.updateCurrentFrameAnnotationState();
    expect(editor.currentFrameText()).toBe('');
    expect(editor.textEditorDraft()).toBe('Unsaved text');
  });

  it('snaps new text annotations to frame boundaries', () => {
    const { editor, service, time } = setup();
    time.set(1.03);
    editor.onTextDraftInput('New text');
    editor.saveTextAnnotation();
    expect(service.upsertAnnotation).toHaveBeenCalledWith('video-1', {
      frameTime: 25 / 24,
      frameRate: 24,
      strokesJSON: '[]',
      text: 'New text',
    });
  });

  it('keeps the draft and allows retry after a failed save', () => {
    const { editor, service } = setup([annotation()]);
    const errorLog = vi.spyOn(console, 'error').mockImplementation(vi.fn());
    service.upsertAnnotation.mockReturnValue(throwError(() => new Error('offline')));
    editor.onTextDraftInput('Retry me');
    editor.saveTextAnnotation();
    expect(editor.textEditorDraft()).toBe('Retry me');
    expect(editor.currentFrameText()).toBe('Saved text');
    expect(editor.textSaveError()).toBe('Save failed');
    expect(editor.canSaveText()).toBe(true);
    errorLog.mockRestore();
  });

  it('cancels loading when its dialog closes', () => {
    const response = new Subject<AnnotationListResponse>();
    const service = {
      getAnnotations: () => response,
      upsertAnnotation: () => of(annotation()),
      deleteAnnotation: () => of(undefined),
    };
    const editor = new AnnotationEditor(service, () => 'video-1', signal(1));
    editor.loadAnnotations();
    editor.destroy();
    response.next({ annotations: [annotation()], total: 1 });
    expect(editor.annotations()).toEqual([]);
    expect(response.observed).toBe(false);
  });

  it('shows annotations without opening the text editor', () => {
    const { editor } = setup();
    editor.toggleAnnotations();
    expect(editor.annotationMode()).toBe(true);
    expect(editor.textEditorOpen()).toBe(false);
  });

  it('opens and closes the text editor while annotations stay visible', () => {
    const { editor } = setup();
    editor.toggleTextEditor();
    expect(editor.textEditorOpen()).toBe(true);
    expect(editor.annotationMode()).toBe(true);
    editor.toggleTextEditor();
    expect(editor.textEditorOpen()).toBe(false);
    expect(editor.annotationMode()).toBe(true);
  });

  it('closes the text editor when annotations are hidden', () => {
    const { editor } = setup();
    editor.toggleTextEditor();
    editor.isTextFocused = true;
    editor.toggleAnnotations();
    expect(editor.annotationMode()).toBe(false);
    expect(editor.textEditorOpen()).toBe(false);
    expect(editor.isTextFocused).toBe(false);
  });
});
