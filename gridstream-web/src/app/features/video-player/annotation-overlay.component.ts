import {
  Component,
  input,
  effect,
  ElementRef,
  ViewChild,
  AfterViewInit,
  OnDestroy,
} from '@angular/core';
import { StrokeData } from '../../core/models/annotation.model';

@Component({
  selector: 'app-annotation-overlay',
  host: { class: 'absolute inset-0 pointer-events-none' },
  template: `<canvas #canvas class="w-full h-full"></canvas>`,
})
export class AnnotationOverlayComponent implements AfterViewInit, OnDestroy {
  strokes = input<StrokeData[]>([]);
  /** Intrinsic width / height of the video; strokes are normalized to the picture, not the box. */
  videoAspect = input<number>(16 / 9);

  @ViewChild('canvas') canvasRef!: ElementRef<HTMLCanvasElement>;

  private resizeObserver: ResizeObserver | null = null;

  constructor() {
    effect(() => {
      const s = this.strokes();
      this.videoAspect();
      this.render(s);
    });
  }

  ngAfterViewInit(): void {
    this.resizeObserver = new ResizeObserver(() => {
      this.render(this.strokes());
    });
    this.resizeObserver.observe(this.canvasRef.nativeElement.parentElement!);
  }

  ngOnDestroy(): void {
    this.resizeObserver?.disconnect();
  }

  // iPad PKCanvasView is ~834pt tall in landscape (iPad Pro 11").
  // Stroke widths are stored in that coordinate space. Scale to match
  // the web container size so strokes appear proportionally correct.
  private static readonly IPAD_REF_HEIGHT = 834;

  private colorWithAlpha(hex: string, opacity: number): string {
    const raw = hex.replace('#', '');
    let r = 0,
      g = 0,
      b = 0;
    if (raw.length >= 6) {
      r = parseInt(raw.substring(0, 2), 16);
      g = parseInt(raw.substring(2, 4), 16);
      b = parseInt(raw.substring(4, 6), 16);
    } else if (raw.length >= 3) {
      r = parseInt(raw[0] + raw[0], 16);
      g = parseInt(raw[1] + raw[1], 16);
      b = parseInt(raw[2] + raw[2], 16);
    }
    // Guard against NaN from bad hex
    if (isNaN(r)) r = 255;
    if (isNaN(g)) g = 0;
    if (isNaN(b)) b = 0;
    // PencilKit's "black" ink (#000000) is adaptive — it renders as white
    // in dark mode on iPad. Since the video background is always dark,
    // invert near-black colors to white to match iPad appearance.
    if (r < 20 && g < 20 && b < 20) {
      r = 255;
      g = 255;
      b = 255;
    }
    return `rgba(${r},${g},${b},${opacity})`;
  }

  private render(strokes: StrokeData[]): void {
    const canvas = this.canvasRef?.nativeElement;
    if (!canvas) return;

    const parent = canvas.parentElement;
    if (!parent) return;

    const w = parent.clientWidth;
    const h = parent.clientHeight;
    if (w === 0 || h === 0) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = w * dpr;
    canvas.height = h * dpr;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    if (!strokes.length) return;

    ctx.scale(dpr, dpr);

    // The <video> letterboxes its picture (object-fit: contain) inside the box.
    const rect = videoContentRect(w, h, this.videoAspect());

    // Scale stroke widths from iPad coordinate space to the displayed picture
    const widthScale = rect.height / AnnotationOverlayComponent.IPAD_REF_HEIGHT;

    for (const stroke of strokes) {
      if (stroke.points.length < 2) continue;

      // Match iPad AnnotationRenderUIView: single continuous path per stroke,
      // uniform lineWidth, opacity applied via strokeStyle alpha
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.globalAlpha = 1;
      ctx.strokeStyle = this.colorWithAlpha(stroke.color, stroke.opacity);
      ctx.lineWidth = stroke.width * widthScale;

      ctx.beginPath();
      ctx.moveTo(rect.x + stroke.points[0].x * rect.width, rect.y + stroke.points[0].y * rect.height);
      for (let i = 1; i < stroke.points.length; i++) {
        ctx.lineTo(
          rect.x + stroke.points[i].x * rect.width,
          rect.y + stroke.points[i].y * rect.height,
        );
      }
      ctx.stroke();
    }
  }
}

/**
 * Rectangle actually covered by a video of the given aspect ratio when it is
 * displayed with `object-fit: contain` in a `boxWidth` x `boxHeight` box.
 */
export function videoContentRect(boxWidth: number, boxHeight: number, aspect: number) {
  if (!(aspect > 0) || !Number.isFinite(aspect) || boxHeight <= 0) {
    return { x: 0, y: 0, width: boxWidth, height: boxHeight };
  }
  if (boxWidth / boxHeight > aspect) {
    // Pillarbox: bars left and right.
    const width = boxHeight * aspect;
    return { x: (boxWidth - width) / 2, y: 0, width, height: boxHeight };
  }
  // Letterbox: bars top and bottom.
  const height = boxWidth / aspect;
  return { x: 0, y: (boxHeight - height) / 2, width: boxWidth, height };
}
