import { analyzeReport } from './triage';

describe('report triage fallback', () => {
  const previous = process.env.GEMINI_API_KEY;
  beforeEach(() => { delete process.env.GEMINI_API_KEY; });
  afterAll(() => { if (previous) process.env.GEMINI_API_KEY = previous; });

  it('flags trapped victims as critical and infers rescue need', async () => {
    const result = await analyzeReport({ description:'5 people trapped inside a flooded building', urgencyUser:'medium', peopleAtRisk:5, inputType:'text' });
    expect(result.urgencyAi).toBe('critical');
    expect(result.aiNeeds.rescue).toBe(true);
  });
});
