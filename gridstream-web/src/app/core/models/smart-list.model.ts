export interface SmartListDTO {
  id: string;
  name: string;
  criteria: string;
  createdAt: string;
  updatedAt: string;
}

export interface TagRatingFilter {
  tagId: string;
  minRating?: number;
  maxRating?: number;
  hasRatingFilter: boolean;
}

export type CriteriaType =
  | { type: 'tagsInclude'; tagIds: string[]; tagRatings: TagRatingFilter[] }
  | { type: 'tagsExclude'; tagIds: string[] }
  | { type: 'ratingMin'; value: number }
  | { type: 'ratingMax'; value: number }
  | { type: 'sourceDirectory'; id: string }
  | { type: 'fileSizeMin'; megabytes: number }
  | { type: 'fileSizeMax'; megabytes: number }
  | { type: 'filenameContains'; text: string }
  | { type: 'filenameStartsWith'; text: string }
  | { type: 'filenameEndsWith'; text: string }
  | { type: 'filenameRegex'; pattern: string }
  | { type: 'dateAddedAfter'; date: string }
  | { type: 'dateAddedBefore'; date: string }
  | { type: 'dateModifiedAfter'; date: string }
  | { type: 'dateModifiedBefore'; date: string }
  | { type: 'playCountMin'; value: number }
  | { type: 'playCountMax'; value: number }
  | { type: 'unrated' }
  | { type: 'unplayed' }
  | { type: 'hasAnnotations'; value: boolean }
  | { type: 'annotationCountMin'; value: number }
  | { type: 'annotationCountMax'; value: number }
  | { type: 'hasTextAnnotations'; value: boolean }
  | { type: 'annotationTextSearch'; text: string }
  | { type: 'hasTimeRanges'; value: boolean }
  | { type: 'simpleListInclude'; simpleListId: string }
  | { type: 'smartListInclude'; smartListId: string };

export interface FilterCondition {
  id: string;
  criteriaType: CriteriaType;
  logicOperator: 'AND' | 'OR';
}

export interface SmartListCriteria {
  conditions: FilterCondition[];
}
