import {
  CriteriaType,
  FilterCondition,
  SmartListCriteria,
  TagRatingFilter,
} from '../../core/models/smart-list.model';

/**
 * Shared smart-list condition model.
 *
 * The UI edits `ConditionDraft`s (flat, typed, always fully populated so form
 * controls can bind to them). `toFilterCondition` / `toCriteria` convert drafts
 * to the API shape and drop anything incomplete; `parseCriteria` goes the other
 * way and tolerates legacy stored criteria (non-UUID ids, date-only strings,
 * reference-date numbers, fractional ratings).
 */

export type CriteriaKind = CriteriaType['type'];
export type LogicOperator = FilterCondition['logicOperator'];

export interface ConditionDraft {
  readonly id: string;
  readonly type: CriteriaKind | '';
  readonly logicOperator: LogicOperator;
  /** tagsInclude / tagsExclude */
  readonly tagIds: readonly string[];
  /** tagsInclude: per-tag rating filters (not editable on web, preserved on round trip). */
  readonly tagRatings: readonly TagRatingFilter[];
  /** Integer bound: ratings (0-10), play counts, annotation counts. */
  readonly value: number | null;
  /** hasAnnotations / hasTextAnnotations / hasTimeRanges */
  readonly flag: boolean;
  /** fileSizeMin / fileSizeMax */
  readonly megabytes: number | null;
  /** filename text, filename regex pattern, annotation text search */
  readonly text: string;
  /** Date conditions, as the `YYYY-MM-DD` value of a date input (local day). */
  readonly date: string;
  /** sourceDirectory id, simpleListId or smartListId */
  readonly refId: string;
}

export interface CriteriaOption {
  readonly value: CriteriaKind;
  readonly label: string;
}

export interface CriteriaOptionGroup {
  readonly label: string;
  readonly options: readonly CriteriaOption[];
}

export const CRITERIA_GROUPS: readonly CriteriaOptionGroup[] = [
  {
    label: 'Tags',
    options: [
      { value: 'tagsInclude', label: 'Include Tags' },
      { value: 'tagsExclude', label: 'Exclude Tags' },
    ],
  },
  {
    label: 'Rating',
    options: [
      { value: 'ratingMin', label: 'Min Rating' },
      { value: 'ratingMax', label: 'Max Rating' },
      { value: 'unrated', label: 'No Rating' },
    ],
  },
  { label: 'Source', options: [{ value: 'sourceDirectory', label: 'Source Directory' }] },
  {
    label: 'File Size',
    options: [
      { value: 'fileSizeMin', label: 'Min File Size (MB)' },
      { value: 'fileSizeMax', label: 'Max File Size (MB)' },
    ],
  },
  {
    label: 'Filename',
    options: [
      { value: 'filenameContains', label: 'Filename Contains' },
      { value: 'filenameStartsWith', label: 'Filename Starts With' },
      { value: 'filenameEndsWith', label: 'Filename Ends With' },
      { value: 'filenameRegex', label: 'Filename Regex' },
    ],
  },
  {
    label: 'Date',
    options: [
      { value: 'dateAddedAfter', label: 'Added After' },
      { value: 'dateAddedBefore', label: 'Added Before' },
      { value: 'dateModifiedAfter', label: 'Modified After' },
      { value: 'dateModifiedBefore', label: 'Modified Before' },
    ],
  },
  {
    label: 'Play Count',
    options: [
      { value: 'playCountMin', label: 'Min Plays' },
      { value: 'playCountMax', label: 'Max Plays' },
      { value: 'unplayed', label: 'No Plays' },
    ],
  },
  {
    label: 'Annotations',
    options: [
      { value: 'hasAnnotations', label: 'Has Annotations' },
      { value: 'annotationCountMin', label: 'Min Annotations' },
      { value: 'annotationCountMax', label: 'Max Annotations' },
      { value: 'hasTextAnnotations', label: 'Has Text Annotation' },
      { value: 'annotationTextSearch', label: 'Annotation Text Contains' },
    ],
  },
  { label: 'Segments', options: [{ value: 'hasTimeRanges', label: 'Has Segments' }] },
  {
    label: 'Lists',
    options: [
      { value: 'simpleListInclude', label: 'In Simple List' },
      { value: 'smartListInclude', label: 'In Smart List' },
    ],
  },
];

const KNOWN_KINDS = new Set<string>(
  CRITERIA_GROUPS.flatMap((group) => group.options.map((option) => option.value)),
);

/** Same limits as the server (contracts/decisions.md §2). */
export const MAX_RATING = 10;
export const MAX_PATTERN_LENGTH = 256;
export const MAX_MEGABYTES = 10_000_000;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_INPUT_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
/** Seconds between 1970-01-01 and 2001-01-01 (Foundation's reference date). */
const REFERENCE_DATE_OFFSET_SECONDS = 978_307_200;

// ---------------------------------------------------------------------------
// Drafts
// ---------------------------------------------------------------------------

/** RFC 4122 v4 UUID. `crypto.randomUUID` needs a secure context, which a LAN http:// origin is not. */
export function newConditionId(): string {
  const cryptoApi = globalThis.crypto;
  if (typeof cryptoApi?.randomUUID === 'function') {
    return cryptoApi.randomUUID();
  }
  const bytes = cryptoApi.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

const EMPTY_FIELDS = {
  tagIds: [],
  tagRatings: [],
  value: null,
  flag: true,
  megabytes: null,
  text: '',
  date: '',
  refId: '',
} satisfies Omit<ConditionDraft, 'id' | 'type' | 'logicOperator'>;

function defaultFields(type: CriteriaKind | '') {
  switch (type) {
    case 'ratingMin':
    case 'ratingMax':
      return { ...EMPTY_FIELDS, value: 5 };
    case 'playCountMin':
    case 'playCountMax':
    case 'annotationCountMin':
    case 'annotationCountMax':
      return { ...EMPTY_FIELDS, value: 0 };
    default:
      return EMPTY_FIELDS;
  }
}

export function createCondition(
  type: CriteriaKind | '' = '',
  overrides: Partial<Omit<ConditionDraft, 'id' | 'type'>> = {},
): ConditionDraft {
  return {
    id: newConditionId(),
    type,
    logicOperator: 'AND',
    ...defaultFields(type),
    ...overrides,
  };
}

/** Switches a draft to another criteria type, resetting its value fields. */
export function withType(draft: ConditionDraft, type: CriteriaKind | ''): ConditionDraft {
  return { ...draft, type, ...defaultFields(type) };
}

export function updateCondition(
  drafts: readonly ConditionDraft[],
  id: string,
  patch: Partial<Omit<ConditionDraft, 'id'>>,
): ConditionDraft[] {
  return drafts.map((draft) => {
    if (draft.id !== id) return draft;
    const tagIds = patch.tagIds;
    // Keep per-tag rating filters only for tags that are still selected.
    const tagRatings = tagIds
      ? draft.tagRatings.filter((rating) => tagIds.includes(rating.tagId))
      : draft.tagRatings;
    return { ...draft, tagRatings, ...patch };
  });
}

// ---------------------------------------------------------------------------
// Draft -> API
// ---------------------------------------------------------------------------

function nonNegativeInteger(value: number | null): number | null {
  if (value === null || !Number.isFinite(value) || value < 0) return null;
  return Math.round(value);
}

function rating(value: number | null): number | null {
  const n = nonNegativeInteger(value);
  return n === null ? null : Math.min(n, MAX_RATING);
}

function pattern(text: string): string | null {
  const trimmed = text.trim();
  return trimmed && trimmed.length <= MAX_PATTERN_LENGTH ? trimmed : null;
}

/** `YYYY-MM-DD` (local day) -> ISO 8601 instant at local midnight. */
export function dateInputToIso(date: string): string | null {
  const match = DATE_INPUT_PATTERN.exec(date);
  if (!match) return null;
  const [, y, m, d] = match.map(Number);
  const local = new Date(y, m - 1, d);
  if (local.getFullYear() !== y || local.getMonth() !== m - 1 || local.getDate() !== d) {
    return null;
  }
  return local.toISOString();
}

/**
 * Converts a draft to the API condition, or `null` when it is incomplete
 * (no type, nothing selected, empty text, invalid number or date).
 */
export function toFilterCondition(draft: ConditionDraft): FilterCondition | null {
  const criteriaType = toCriteriaType(draft);
  return criteriaType
    ? {
        id: isUuid(draft.id) ? draft.id : newConditionId(),
        criteriaType,
        logicOperator: draft.logicOperator,
      }
    : null;
}

function toCriteriaType(d: ConditionDraft): CriteriaType | null {
  switch (d.type) {
    case '':
      return null;
    case 'tagsInclude':
      return d.tagIds.length
        ? {
            type: d.type,
            tagIds: [...d.tagIds],
            tagRatings: d.tagRatings.filter((r) => d.tagIds.includes(r.tagId)),
          }
        : null;
    case 'tagsExclude':
      return d.tagIds.length ? { type: d.type, tagIds: [...d.tagIds] } : null;
    case 'ratingMin':
    case 'ratingMax': {
      const value = rating(d.value);
      return value === null ? null : { type: d.type, value };
    }
    case 'playCountMin':
    case 'playCountMax':
    case 'annotationCountMin':
    case 'annotationCountMax': {
      const value = nonNegativeInteger(d.value);
      return value === null ? null : { type: d.type, value };
    }
    case 'sourceDirectory':
      return d.refId ? { type: d.type, id: d.refId } : null;
    case 'simpleListInclude':
      return d.refId ? { type: d.type, simpleListId: d.refId } : null;
    case 'smartListInclude':
      return d.refId ? { type: d.type, smartListId: d.refId } : null;
    case 'fileSizeMin':
    case 'fileSizeMax': {
      const mb = d.megabytes;
      return mb !== null && Number.isFinite(mb) && mb >= 0 && mb <= MAX_MEGABYTES
        ? { type: d.type, megabytes: mb }
        : null;
    }
    case 'filenameContains':
    case 'filenameStartsWith':
    case 'filenameEndsWith':
    case 'annotationTextSearch': {
      const text = pattern(d.text);
      return text === null ? null : { type: d.type, text };
    }
    case 'filenameRegex': {
      const text = pattern(d.text);
      return text === null ? null : { type: d.type, pattern: text };
    }
    case 'dateAddedAfter':
    case 'dateAddedBefore':
    case 'dateModifiedAfter':
    case 'dateModifiedBefore': {
      const date = dateInputToIso(d.date);
      return date === null ? null : { type: d.type, date };
    }
    case 'unrated':
    case 'unplayed':
      return { type: d.type };
    case 'hasAnnotations':
    case 'hasTextAnnotations':
    case 'hasTimeRanges':
      return { type: d.type, value: d.flag };
  }
}

export function isComplete(draft: ConditionDraft): boolean {
  return toCriteriaType(draft) !== null;
}

/** Complete conditions only; `null` when nothing is left to filter on. */
export function toCriteria(drafts: readonly ConditionDraft[]): SmartListCriteria | null {
  const conditions = drafts
    .map(toFilterCondition)
    .filter((condition): condition is FilterCondition => condition !== null);
  return conditions.length ? { conditions } : null;
}

/** JSON for the `criteria` query parameter / smart list body, or `null` when empty. */
export function serializeCriteria(drafts: readonly ConditionDraft[]): string | null {
  const criteria = toCriteria(drafts);
  return criteria ? JSON.stringify(criteria) : null;
}

// ---------------------------------------------------------------------------
// API -> Draft
// ---------------------------------------------------------------------------

function pad(n: number): string {
  return n.toString().padStart(2, '0');
}

/** Any stored date representation -> `YYYY-MM-DD` of the local day, or '' when unreadable. */
export function isoToDateInput(value: unknown): string {
  if (typeof value === 'string' && DATE_INPUT_PATTERN.test(value)) return value;
  let date: Date | null = null;
  if (typeof value === 'string') {
    date = new Date(value);
  } else if (typeof value === 'number' && Number.isFinite(value)) {
    // Legacy iPad encoding: seconds since 2001-01-01 (JSONEncoder .deferredToDate).
    date = new Date((value + REFERENCE_DATE_OFFSET_SECONDS) * 1000);
  }
  if (!date || Number.isNaN(date.getTime())) return '';
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function asNumber(value: unknown): number | null {
  const n = typeof value === 'string' ? Number(value) : value;
  return typeof n === 'number' && Number.isFinite(n) ? n : null;
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : [];
}

export function fromFilterCondition(condition: FilterCondition): ConditionDraft {
  const raw = (condition.criteriaType ?? {}) as unknown as Record<string, unknown>;
  const type = KNOWN_KINDS.has(String(raw['type'])) ? (raw['type'] as CriteriaKind) : '';
  const base = createCondition(type, {
    logicOperator: condition.logicOperator === 'OR' ? 'OR' : 'AND',
  });
  const id = isUuid(condition.id) ? condition.id : base.id;

  switch (type) {
    case 'tagsInclude':
    case 'tagsExclude':
      return {
        ...base,
        id,
        tagIds: asStringArray(raw['tagIds']),
        tagRatings: Array.isArray(raw['tagRatings'])
          ? (raw['tagRatings'] as TagRatingFilter[])
          : [],
      };
    case 'ratingMin':
    case 'ratingMax': {
      const value = asNumber(raw['value']);
      return { ...base, id, value: value === null ? null : rating(value) };
    }
    case 'playCountMin':
    case 'playCountMax':
    case 'annotationCountMin':
    case 'annotationCountMax':
      return { ...base, id, value: nonNegativeInteger(asNumber(raw['value'])) };
    case 'sourceDirectory':
      return { ...base, id, refId: asString(raw['id']) };
    case 'simpleListInclude':
      return { ...base, id, refId: asString(raw['simpleListId']) };
    case 'smartListInclude':
      return { ...base, id, refId: asString(raw['smartListId']) };
    case 'fileSizeMin':
    case 'fileSizeMax':
      return { ...base, id, megabytes: asNumber(raw['megabytes']) };
    case 'filenameContains':
    case 'filenameStartsWith':
    case 'filenameEndsWith':
    case 'annotationTextSearch':
      return { ...base, id, text: asString(raw['text']) };
    case 'filenameRegex':
      return { ...base, id, text: asString(raw['pattern']) };
    case 'dateAddedAfter':
    case 'dateAddedBefore':
    case 'dateModifiedAfter':
    case 'dateModifiedBefore':
      return { ...base, id, date: isoToDateInput(raw['date']) };
    case 'hasAnnotations':
    case 'hasTextAnnotations':
    case 'hasTimeRanges':
      return { ...base, id, flag: raw['value'] !== false };
    default:
      return { ...base, id };
  }
}

/** Parses stored criteria JSON. Invalid JSON yields no conditions rather than throwing. */
export function parseCriteria(json: string | null | undefined): ConditionDraft[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json) as Partial<SmartListCriteria> | null;
    return Array.isArray(parsed?.conditions) ? parsed.conditions.map(fromFilterCondition) : [];
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

export interface CriteriaLookups {
  readonly tags?: readonly { id: string; name: string }[];
  readonly sources?: readonly { id: string; name: string }[];
  readonly simpleLists?: readonly { id: string; name: string }[];
  readonly smartLists?: readonly { id: string; name: string }[];
}

function nameOf(items: readonly { id: string; name: string }[] | undefined, id: string) {
  return items?.find((item) => item.id === id)?.name;
}

/** Short human-readable label for a condition chip. */
export function describeCondition(d: ConditionDraft, lookups: CriteriaLookups = {}): string {
  const tagNames = () =>
    d.tagIds
      .map((id) => nameOf(lookups.tags, id))
      .filter(Boolean)
      .join(', ') || '(none)';

  switch (d.type) {
    case '':
      return '(incomplete)';
    case 'tagsInclude':
      return `Tags: ${tagNames()}`;
    case 'tagsExclude':
      return `Exclude Tags: ${tagNames()}`;
    case 'ratingMin':
      return `Rating >= ${d.value ?? '?'}`;
    case 'ratingMax':
      return `Rating <= ${d.value ?? '?'}`;
    case 'sourceDirectory':
      return `Source: ${nameOf(lookups.sources, d.refId) ?? '(unknown)'}`;
    case 'fileSizeMin':
      return `Size >= ${d.megabytes ?? '?'} MB`;
    case 'fileSizeMax':
      return `Size <= ${d.megabytes ?? '?'} MB`;
    case 'filenameContains':
      return `Filename contains "${d.text}"`;
    case 'filenameStartsWith':
      return `Filename starts with "${d.text}"`;
    case 'filenameEndsWith':
      return `Filename ends with "${d.text}"`;
    case 'filenameRegex':
      return `Filename regex: ${d.text}`;
    case 'dateAddedAfter':
      return `Added after ${d.date}`;
    case 'dateAddedBefore':
      return `Added before ${d.date}`;
    case 'dateModifiedAfter':
      return `Modified after ${d.date}`;
    case 'dateModifiedBefore':
      return `Modified before ${d.date}`;
    case 'playCountMin':
      return `Plays >= ${d.value ?? '?'}`;
    case 'playCountMax':
      return `Plays <= ${d.value ?? '?'}`;
    case 'unrated':
      return 'Unrated';
    case 'unplayed':
      return 'Unplayed';
    case 'hasAnnotations':
      return d.flag ? 'Has Annotations' : 'No Annotations';
    case 'annotationCountMin':
      return `Annotations >= ${d.value ?? '?'}`;
    case 'annotationCountMax':
      return `Annotations <= ${d.value ?? '?'}`;
    case 'hasTextAnnotations':
      return d.flag ? 'Has Text Annotation' : 'No Text Annotation';
    case 'annotationTextSearch':
      return `Annotation text contains "${d.text}"`;
    case 'hasTimeRanges':
      return d.flag ? 'Has Segments' : 'No Segments';
    case 'simpleListInclude':
      return `In List: ${nameOf(lookups.simpleLists, d.refId) ?? '(none)'}`;
    case 'smartListInclude':
      return `In Smart List: ${nameOf(lookups.smartLists, d.refId) ?? '(none)'}`;
  }
}
