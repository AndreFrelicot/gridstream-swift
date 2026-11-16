import { videoContentRect } from './annotation-overlay.component';

describe('videoContentRect', () => {
  it('fills the box when the aspect ratios match', () => {
    expect(videoContentRect(1600, 900, 16 / 9)).toEqual({ x: 0, y: 0, width: 1600, height: 900 });
  });

  it('pillarboxes a portrait video in a 16:9 box', () => {
    const rect = videoContentRect(1600, 900, 9 / 16);
    expect(rect.height).toBe(900);
    expect(rect.width).toBeCloseTo(506.25);
    expect(rect.x).toBeCloseTo((1600 - 506.25) / 2);
    expect(rect.y).toBe(0);
  });

  it('letterboxes a 2.39:1 video in a 16:9 box', () => {
    const rect = videoContentRect(1600, 900, 2.39);
    expect(rect.width).toBe(1600);
    expect(rect.height).toBeCloseTo(1600 / 2.39);
    expect(rect.y).toBeCloseTo((900 - 1600 / 2.39) / 2);
  });

  it('falls back to the whole box for an unknown aspect', () => {
    expect(videoContentRect(800, 450, 0)).toEqual({ x: 0, y: 0, width: 800, height: 450 });
  });
});
