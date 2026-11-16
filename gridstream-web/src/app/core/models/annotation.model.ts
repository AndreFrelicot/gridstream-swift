export interface StrokePoint {
  x: number; // 0.0-1.0 normalized to video dimensions
  y: number;
  pressure: number; // 0.0-1.0
}

export interface StrokeData {
  color: string; // hex e.g. "#FF0000"
  width: number;
  opacity: number;
  points: StrokePoint[];
}

export interface AnnotationInfo {
  id: string;
  videoFileId: string;
  frameTime: number;
  frameRate: number;
  strokesJSON: string;
  text?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface UpsertAnnotationRequest {
  frameTime: number;
  frameRate: number;
  strokesJSON: string;
  text: string | null;
}

export interface AnnotationListResponse {
  annotations: AnnotationInfo[];
  total: number;
}
