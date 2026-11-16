import {
  DurationPipe,
  FileSizePipe,
  RelativeTimePipe,
  formatDuration,
  formatFileSize,
  formatRelativeTime,
} from './format';

describe('format pipes', () => {
  describe('duration', () => {
    it('formats minutes and hours', () => {
      expect(formatDuration(0)).toBe('0:00');
      expect(formatDuration(5.9)).toBe('0:05');
      expect(formatDuration(65)).toBe('1:05');
      expect(formatDuration(3600)).toBe('1:00:00');
      expect(formatDuration(3725)).toBe('1:02:05');
    });

    it('renders invalid input as zero', () => {
      expect(formatDuration(NaN)).toBe('0:00');
      expect(formatDuration(Infinity)).toBe('0:00');
      expect(formatDuration(-3)).toBe('0:00');
      expect(formatDuration(null)).toBe('0:00');
      expect(new DurationPipe().transform(125)).toBe('2:05');
    });
  });

  describe('fileSize', () => {
    it('uses binary units with one decimal', () => {
      expect(formatFileSize(512)).toBe('512 B');
      expect(formatFileSize(1536)).toBe('1.5 KB');
      expect(formatFileSize(5 * 1024 * 1024)).toBe('5.0 MB');
      expect(formatFileSize(1.25 * 1024 ** 3)).toBe('1.3 GB');
      expect(formatFileSize(3 * 1024 ** 4)).toBe('3.0 TB');
    });

    it('handles invalid input', () => {
      expect(formatFileSize(-1)).toBe('—');
      expect(formatFileSize(undefined)).toBe('—');
      expect(new FileSizePipe().transform(2048)).toBe('2.0 KB');
    });
  });

  describe('relativeTime', () => {
    const now = Date.UTC(2026, 10, 3, 12, 0, 0);
    const ago = (ms: number) => new Date(now - ms).toISOString();

    it('formats recent times', () => {
      expect(formatRelativeTime(ago(10_000), now)).toBe('Just now');
      expect(formatRelativeTime(ago(5 * 60_000), now)).toBe('5m ago');
      expect(formatRelativeTime(ago(3 * 3_600_000), now)).toBe('3h ago');
      expect(formatRelativeTime(ago(12 * 86_400_000), now)).toBe('12d ago');
    });

    it('falls back to the local date after 30 days', () => {
      const old = ago(40 * 86_400_000);
      expect(formatRelativeTime(old, now)).toBe(new Date(old).toLocaleDateString());
    });

    it('handles missing or invalid dates', () => {
      expect(formatRelativeTime(null, now)).toBe('—');
      expect(formatRelativeTime('', now)).toBe('—');
      expect(formatRelativeTime('nope', now)).toBe('—');
      expect(new RelativeTimePipe().transform(undefined)).toBe('—');
    });
  });
});
