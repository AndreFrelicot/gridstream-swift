export interface TimeRangeInfo {
  id: string;
  videoFileId: string;
  startTime: number;
  endTime: number;
  label?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface TimeRangeListResponse {
  timeRanges: TimeRangeInfo[];
  total: number;
}
