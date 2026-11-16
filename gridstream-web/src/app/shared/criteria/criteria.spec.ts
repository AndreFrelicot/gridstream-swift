import { CriteriaType, FilterCondition } from '../../core/models/smart-list.model';
import {
  ConditionDraft,
  CriteriaKind,
  createCondition,
  dateInputToIso,
  describeCondition,
  fromFilterCondition,
  isComplete,
  isUuid,
  isoToDateInput,
  newConditionId,
  parseCriteria,
  serializeCriteria,
  toCriteria,
  toFilterCondition,
  updateCondition,
  withType,
} from './criteria';

const TAG_A = '11111111-1111-4111-8111-111111111111';
const TAG_B = '22222222-2222-4222-8222-222222222222';
const SOURCE = '33333333-3333-4333-8333-333333333333';
const LIST = '44444444-4444-4444-8444-444444444444';

function criteriaTypeOf(draft: ConditionDraft): CriteriaType {
  const condition = toFilterCondition(draft);
  expect(condition).not.toBeNull();
  return condition!.criteriaType;
}

describe('criteria builder', () => {
  describe('ids', () => {
    it('creates RFC 4122 v4 UUIDs', () => {
      const ids = new Set(Array.from({ length: 50 }, () => newConditionId()));
      expect(ids.size).toBe(50);
      for (const id of ids) {
        expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
      }
    });

    it('falls back to getRandomValues outside a secure context', () => {
      const original = crypto.randomUUID;
      Object.defineProperty(crypto, 'randomUUID', { value: undefined, configurable: true });
      try {
        expect(isUuid(newConditionId())).toBe(true);
      } finally {
        Object.defineProperty(crypto, 'randomUUID', { value: original, configurable: true });
      }
    });

    it('gives every new condition a UUID and keeps it through serialization', () => {
      const draft = createCondition('unrated');
      expect(isUuid(draft.id)).toBe(true);
      expect(toFilterCondition(draft)?.id).toBe(draft.id);
    });

    it('replaces legacy non-UUID ids when parsing', () => {
      const [draft] = parseCriteria(
        JSON.stringify({
          conditions: [{ id: 'k3j2h1', criteriaType: { type: 'unplayed' }, logicOperator: 'AND' }],
        }),
      );
      expect(isUuid(draft.id)).toBe(true);
    });
  });

  describe('serialization of every criteria type', () => {
    const cases: [CriteriaKind, Partial<ConditionDraft>, CriteriaType][] = [
      [
        'tagsInclude',
        { tagIds: [TAG_A, TAG_B] },
        { type: 'tagsInclude', tagIds: [TAG_A, TAG_B], tagRatings: [] },
      ],
      ['tagsExclude', { tagIds: [TAG_A] }, { type: 'tagsExclude', tagIds: [TAG_A] }],
      ['ratingMin', { value: 7 }, { type: 'ratingMin', value: 7 }],
      ['ratingMax', { value: 3 }, { type: 'ratingMax', value: 3 }],
      ['unrated', {}, { type: 'unrated' }],
      ['sourceDirectory', { refId: SOURCE }, { type: 'sourceDirectory', id: SOURCE }],
      ['fileSizeMin', { megabytes: 12.5 }, { type: 'fileSizeMin', megabytes: 12.5 }],
      ['fileSizeMax', { megabytes: 0 }, { type: 'fileSizeMax', megabytes: 0 }],
      ['filenameContains', { text: ' clip ' }, { type: 'filenameContains', text: 'clip' }],
      ['filenameStartsWith', { text: 'IMG' }, { type: 'filenameStartsWith', text: 'IMG' }],
      ['filenameEndsWith', { text: '.mov' }, { type: 'filenameEndsWith', text: '.mov' }],
      ['filenameRegex', { text: '^a.+z$' }, { type: 'filenameRegex', pattern: '^a.+z$' }],
      ['playCountMin', { value: 2 }, { type: 'playCountMin', value: 2 }],
      ['playCountMax', { value: 0 }, { type: 'playCountMax', value: 0 }],
      ['unplayed', {}, { type: 'unplayed' }],
      ['hasAnnotations', { flag: false }, { type: 'hasAnnotations', value: false }],
      ['annotationCountMin', { value: 1 }, { type: 'annotationCountMin', value: 1 }],
      ['annotationCountMax', { value: 9 }, { type: 'annotationCountMax', value: 9 }],
      ['hasTextAnnotations', { flag: true }, { type: 'hasTextAnnotations', value: true }],
      ['annotationTextSearch', { text: 'goal' }, { type: 'annotationTextSearch', text: 'goal' }],
      ['hasTimeRanges', { flag: true }, { type: 'hasTimeRanges', value: true }],
      ['simpleListInclude', { refId: LIST }, { type: 'simpleListInclude', simpleListId: LIST }],
      ['smartListInclude', { refId: LIST }, { type: 'smartListInclude', smartListId: LIST }],
    ];

    it.each(cases)('%s', (type, fields, expected) => {
      const draft = { ...createCondition(type), ...fields };
      expect(criteriaTypeOf(draft)).toEqual(expected);
      // Round trip back to an equivalent draft.
      const parsed = fromFilterCondition(toFilterCondition(draft)!);
      expect(criteriaTypeOf(parsed)).toEqual(expected);
      expect(parsed.id).toBe(draft.id);
    });

    it('covers every date type with a full ISO string at local midnight', () => {
      for (const type of [
        'dateAddedAfter',
        'dateAddedBefore',
        'dateModifiedAfter',
        'dateModifiedBefore',
      ] as const) {
        const result = criteriaTypeOf({ ...createCondition(type), date: '2025-01-15' });
        expect(result).toEqual({ type, date: new Date(2025, 0, 15).toISOString() });
        expect((result as { date: string }).date).toMatch(
          /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/,
        );
      }
    });
  });

  describe('ratings', () => {
    it('sends integers clamped to 0...10', () => {
      expect(criteriaTypeOf({ ...createCondition('ratingMin'), value: 7.5 })).toEqual({
        type: 'ratingMin',
        value: 8,
      });
      expect(criteriaTypeOf({ ...createCondition('ratingMax'), value: 42 })).toEqual({
        type: 'ratingMax',
        value: 10,
      });
    });

    it('rounds fractional ratings from stored criteria', () => {
      const draft = fromFilterCondition({
        id: newConditionId(),
        criteriaType: { type: 'ratingMin', value: 6.6 },
        logicOperator: 'AND',
      });
      expect(draft.value).toBe(7);
    });

    it('defaults to an integer', () => {
      expect(Number.isInteger(createCondition('ratingMin').value)).toBe(true);
    });
  });

  describe('dates', () => {
    it('converts a date input value to ISO and back to the same local day', () => {
      const iso = dateInputToIso('2024-02-29')!;
      expect(iso).toBe(new Date(2024, 1, 29).toISOString());
      expect(isoToDateInput(iso)).toBe('2024-02-29');
    });

    it('rejects empty and impossible dates', () => {
      expect(dateInputToIso('')).toBeNull();
      expect(dateInputToIso('2023-02-30')).toBeNull();
      expect(dateInputToIso('15/01/2025')).toBeNull();
    });

    it('reads legacy date-only strings and reference-date numbers', () => {
      expect(isoToDateInput('2025-01-15')).toBe('2025-01-15');
      // 2001-01-01T12:00:00Z expressed as seconds since the Foundation reference date.
      const expected = new Date(Date.UTC(2001, 0, 1, 12));
      const local = `${expected.getFullYear()}-${String(expected.getMonth() + 1).padStart(2, '0')}-${String(expected.getDate()).padStart(2, '0')}`;
      expect(isoToDateInput(43_200)).toBe(local);
      expect(isoToDateInput('not a date')).toBe('');
    });
  });

  describe('incomplete conditions are never sent', () => {
    const incomplete: ConditionDraft[] = [
      createCondition(),
      createCondition('tagsInclude'),
      createCondition('tagsExclude'),
      { ...createCondition('ratingMin'), value: null },
      { ...createCondition('ratingMax'), value: -1 },
      createCondition('sourceDirectory'),
      createCondition('fileSizeMin'),
      { ...createCondition('fileSizeMax'), megabytes: -5 },
      { ...createCondition('filenameContains'), text: '   ' },
      { ...createCondition('filenameRegex'), text: 'x'.repeat(257) },
      createCondition('dateAddedAfter'),
      { ...createCondition('playCountMin'), value: null },
      createCondition('simpleListInclude'),
      createCondition('smartListInclude'),
      createCondition('annotationTextSearch'),
    ];

    it.each(incomplete.map((d) => [d.type || '(none)', d] as const))('%s', (_, draft) => {
      expect(isComplete(draft)).toBe(false);
      expect(toFilterCondition(draft)).toBeNull();
    });

    it('drops them from the criteria and returns null when nothing is left', () => {
      expect(toCriteria(incomplete)).toBeNull();
      expect(serializeCriteria(incomplete)).toBeNull();

      const unplayed = createCondition('unplayed');
      const criteria = toCriteria([...incomplete, unplayed]);
      expect(criteria?.conditions).toHaveLength(1);
      expect(criteria?.conditions[0].id).toBe(unplayed.id);
    });
  });

  describe('editing', () => {
    it('updates immutably', () => {
      const drafts = [createCondition('filenameContains'), createCondition('unrated')];
      const next = updateCondition(drafts, drafts[0].id, { text: 'abc' });
      expect(next).not.toBe(drafts);
      expect(next[0]).not.toBe(drafts[0]);
      expect(next[1]).toBe(drafts[1]);
      expect(drafts[0].text).toBe('');
      expect(next[0].text).toBe('abc');
    });

    it('drops tag rating filters for deselected tags', () => {
      const draft: ConditionDraft = {
        ...createCondition('tagsInclude'),
        tagIds: [TAG_A, TAG_B],
        tagRatings: [
          { tagId: TAG_A, minRating: 3, hasRatingFilter: true },
          { tagId: TAG_B, maxRating: 8, hasRatingFilter: true },
        ],
      };
      const [next] = updateCondition([draft], draft.id, { tagIds: [TAG_B] });
      expect(next.tagRatings).toEqual([{ tagId: TAG_B, maxRating: 8, hasRatingFilter: true }]);
    });

    it('resets values when the type changes but keeps id and operator', () => {
      const draft = {
        ...createCondition('filenameContains'),
        text: 'abc',
        logicOperator: 'OR' as const,
      };
      const next = withType(draft, 'ratingMin');
      expect(next.id).toBe(draft.id);
      expect(next.logicOperator).toBe('OR');
      expect(next.text).toBe('');
      expect(next.value).toBe(5);
    });
  });

  describe('parsing', () => {
    it('returns no conditions for invalid or empty JSON', () => {
      expect(parseCriteria('')).toEqual([]);
      expect(parseCriteria('{oops')).toEqual([]);
      expect(parseCriteria('{"conditions":null}')).toEqual([]);
    });

    it('keeps logic operators', () => {
      const conditions: FilterCondition[] = [
        { id: newConditionId(), criteriaType: { type: 'unrated' }, logicOperator: 'AND' },
        { id: newConditionId(), criteriaType: { type: 'unplayed' }, logicOperator: 'OR' },
      ];
      const drafts = parseCriteria(JSON.stringify({ conditions }));
      expect(drafts.map((d) => d.logicOperator)).toEqual(['AND', 'OR']);
      expect(toCriteria(drafts)).toEqual({ conditions });
    });
  });

  describe('labels', () => {
    it('resolves names from lookups', () => {
      const draft = { ...createCondition('tagsInclude'), tagIds: [TAG_A] };
      expect(describeCondition(draft, { tags: [{ id: TAG_A, name: 'Goal' }] })).toBe('Tags: Goal');
      expect(describeCondition({ ...createCondition('sourceDirectory'), refId: SOURCE })).toBe(
        'Source: (unknown)',
      );
    });
  });
});
