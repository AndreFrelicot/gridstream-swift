import { computed, signal, Signal } from '@angular/core';
import { Subscription } from 'rxjs';
import { AnnotationInfo, StrokeData } from '../../core/models/annotation.model';
import { AnnotationService } from '../../core/services/annotation.service';

export class AnnotationEditor {
  // Annotation state
  annotationMode = signal(false);
  /** The text editor panel opens on its own, so annotations can be watched without it. */
  textEditorOpen = signal(false);
  annotations = signal<AnnotationInfo[]>([]);
  annotationTimes = signal<number[]>([]);
  currentFrameStrokes = signal<StrokeData[]>([]);
  currentFrameText = signal('');
  frameRate = signal(24);
  hasCurrentFrameText = computed(() => this.currentFrameText().trim().length > 0);
  currentFrameTime = computed(() => this.getSnappedCurrentFrameTime());
  textEditorDraft = signal('');
  /** True while the user is typing or has unsaved text: playback must not overwrite the draft. */
  private textDraftDirty = false;
  isTextFocused = false;
  isSavingText = signal(false);
  textSaveError = signal('');
  canSaveText = computed(
    () =>
      !this.isSavingText() &&
      this.normalizeTextForComparison(this.textEditorDraft()) !==
        this.normalizeTextForComparison(this.currentFrameText()),
  );
  canClearText = computed(
    () =>
      this.normalizeTextForComparison(this.textEditorDraft()).length > 0 ||
      this.normalizeTextForComparison(this.currentFrameText()).length > 0,
  );

  private readonly subscriptions = new Subscription();

  constructor(
    private readonly annotationService: Pick<
      AnnotationService,
      'getAnnotations' | 'upsertAnnotation' | 'deleteAnnotation'
    >,
    private readonly fileId: () => string,
    private readonly currentTime: Signal<number>,
  ) {}

  loadAnnotations(): void {
    const fileId = this.fileId();
    this.subscriptions.add(
      this.annotationService.getAnnotations(fileId).subscribe({
        next: (annRes) => this.replaceAnnotations(annRes.annotations),
        error: (err) => console.error('Failed to load annotations:', err),
      }),
    );
  }

  destroy(): void {
    this.subscriptions.unsubscribe();
  }

  /** Hiding the annotations also closes the text editor. */
  toggleAnnotations(): void {
    const visible = !this.annotationMode();
    this.annotationMode.set(visible);
    if (!visible) this.closeTextEditor();
  }

  /** Opening the text editor shows the annotations it edits. */
  toggleTextEditor(): void {
    if (this.textEditorOpen()) {
      this.closeTextEditor();
    } else {
      this.textEditorOpen.set(true);
      this.annotationMode.set(true);
    }
  }

  private closeTextEditor(): void {
    this.textEditorOpen.set(false);
    // The textarea leaves the page without a blur event.
    this.isTextFocused = false;
  }

  onTextDraftInput(value: string): void {
    this.textEditorDraft.set(value);
    this.textDraftDirty = true;
    this.textSaveError.set('');
  }

  /** Copies the current frame's saved text into the editor unless the user is editing it. */
  private syncTextDraft(text: string): void {
    if (this.isTextFocused || this.textDraftDirty) return;
    this.textEditorDraft.set(text);
  }

  saveTextAnnotation(): void {
    if (!this.canSaveText()) return;

    const fileId = this.fileId();
    const existing = this.findAnnotationForCurrentFrame();
    const normalizedText = this.normalizeTextForRequest(this.textEditorDraft());

    if (existing && normalizedText === null && !this.annotationHasStrokes(existing)) {
      this.isSavingText.set(true);
      this.textSaveError.set('');
      this.subscriptions.add(
        this.annotationService.deleteAnnotation(fileId, existing.id).subscribe({
          next: () => {
            this.isSavingText.set(false);
            this.textDraftDirty = false;
            this.replaceAnnotations(
              this.annotations().filter((annotation) => annotation.id !== existing.id),
            );
          },
          error: (err) => {
            console.error('Failed to delete text annotation:', err);
            this.isSavingText.set(false);
            this.textSaveError.set('Delete failed');
          },
        }),
      );
      return;
    }

    if (!existing && normalizedText === null) {
      return;
    }

    this.isSavingText.set(true);
    this.textSaveError.set('');
    this.subscriptions.add(
      this.annotationService
        .upsertAnnotation(fileId, {
          frameTime: existing?.frameTime ?? this.getSnappedCurrentFrameTime(),
          frameRate: existing?.frameRate ?? this.frameRate(),
          strokesJSON: existing?.strokesJSON ?? '[]',
          text: normalizedText,
        })
        .subscribe({
          next: (savedAnnotation) => {
            this.isSavingText.set(false);
            this.textDraftDirty = false;
            this.mergeAnnotation(savedAnnotation);
          },
          error: (err) => {
            console.error('Failed to save text annotation:', err);
            this.isSavingText.set(false);
            this.textSaveError.set('Save failed');
          },
        }),
    );
  }

  clearTextAnnotation(): void {
    this.textEditorDraft.set('');
    this.textDraftDirty = true;
    this.textSaveError.set('');
  }

  updateCurrentFrameAnnotationState(): void {
    const anns = this.annotations();
    if (anns.length === 0) {
      this.currentFrameStrokes.set([]);
      this.currentFrameText.set('');
      this.syncTextDraft('');
      return;
    }

    const match = this.findAnnotationForCurrentFrame();
    if (match) {
      this.currentFrameText.set(match.text ?? '');
      this.syncTextDraft(match.text ?? '');
      try {
        const strokes: StrokeData[] = JSON.parse(match.strokesJSON);
        this.currentFrameStrokes.set(strokes);
      } catch {
        this.currentFrameStrokes.set([]);
      }
    } else {
      this.currentFrameStrokes.set([]);
      this.currentFrameText.set('');
      this.syncTextDraft('');
    }
  }

  private replaceAnnotations(annotations: AnnotationInfo[]): void {
    const sortedAnnotations = [...annotations].sort((a, b) => a.frameTime - b.frameTime);
    this.annotations.set(sortedAnnotations);
    this.annotationTimes.set(sortedAnnotations.map((annotation) => annotation.frameTime));
    if (sortedAnnotations.length > 0) {
      this.frameRate.set(sortedAnnotations[0].frameRate);
    }
    this.updateCurrentFrameAnnotationState();
  }

  private mergeAnnotation(annotation: AnnotationInfo): void {
    const nextAnnotations = [...this.annotations()];
    const existingIndex = nextAnnotations.findIndex((item) => item.id === annotation.id);
    if (existingIndex >= 0) {
      nextAnnotations[existingIndex] = annotation;
    } else {
      const currentFrameIndex = this.findMatchingAnnotationIndex(
        annotation.frameTime,
        annotation.frameRate,
      );
      if (currentFrameIndex >= 0) {
        nextAnnotations[currentFrameIndex] = annotation;
      } else {
        nextAnnotations.push(annotation);
      }
    }

    this.frameRate.set(annotation.frameRate);
    this.replaceAnnotations(nextAnnotations);
  }

  private findAnnotationForCurrentFrame(): AnnotationInfo | undefined {
    const index = this.findMatchingAnnotationIndex(this.currentTime(), this.frameRate());
    return index >= 0 ? this.annotations()[index] : undefined;
  }

  private findMatchingAnnotationIndex(time: number, frameRate: number): number {
    const frameDuration = frameRate > 0 ? 1.0 / frameRate : 0.04;
    return this.annotations().findIndex(
      (annotation) => Math.abs(time - annotation.frameTime) < frameDuration * 0.5,
    );
  }

  private getSnappedCurrentFrameTime(): number {
    const frameRate = this.frameRate();
    if (frameRate <= 0) {
      return this.currentTime();
    }
    return Math.round(this.currentTime() * frameRate) / frameRate;
  }

  private normalizeTextForRequest(value: string): string | null {
    return value.trim().length > 0 ? value : null;
  }

  private normalizeTextForComparison(value: string): string {
    return value.replace(/\r\n/g, '\n');
  }

  private annotationHasStrokes(annotation: AnnotationInfo): boolean {
    try {
      const strokes = JSON.parse(annotation.strokesJSON) as StrokeData[];
      return Array.isArray(strokes) && strokes.length > 0;
    } catch {
      return false;
    }
  }
}
