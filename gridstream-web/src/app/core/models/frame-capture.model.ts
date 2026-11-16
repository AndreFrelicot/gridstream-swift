export interface FrameCaptureInfo {
  id: string;
  fileId: string;
  timestamp: number;
  width: number;
  height: number;
  fileSize: number;
  createdAt: string;
  filename: string | null;
}

export interface FrameCaptureListResponse {
  captures: FrameCaptureInfo[];
  total: number;
}
