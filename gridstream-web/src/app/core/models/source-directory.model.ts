export interface SourceDirectoryInfo {
  id: string;
  name: string;
  path?: string;
}

export interface SourceDirectoriesResponse {
  directories: SourceDirectoryInfo[];
}
