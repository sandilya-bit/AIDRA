describe('Operations algorithms & data contracts', () => {
  function haversineKm(
    a: { latitude: number; longitude: number },
    b: { latitude: number; longitude: number }
  ): number {
    const rad = (x: number) => (x * Math.PI) / 180;
    const dLat = rad(b.latitude - a.latitude);
    const dLon = rad(b.longitude - a.longitude);
    const h =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(rad(a.latitude)) *
        Math.cos(rad(b.latitude)) *
        Math.sin(dLon / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
  }

  it('calculates Haversine distance accurately between coordinates', () => {
    const hydCenter = { latitude: 17.385, longitude: 78.4867 };
    const secunderabad = { latitude: 17.4399, longitude: 78.4983 };
    const dist = haversineKm(hydCenter, secunderabad);

    expect(dist).toBeGreaterThan(5.0);
    expect(dist).toBeLessThan(7.5);
  });

  it('correctly scores volunteer skill fit and distance rank', () => {
    const incidentLocation = { latitude: 17.385, longitude: 78.4867 };
    const requiredSkills = ['rescue', 'first-aid'];
    const radiusKm = 10;

    const volunteers = [
      {
        id: 'vol-1',
        name: 'Arjun Patel',
        skills: ['rescue', 'medical'],
        location: { latitude: 17.395, longitude: 78.489 },
      },
      {
        id: 'vol-2',
        name: 'Sneha Reddy',
        skills: ['rescue', 'first-aid'],
        location: { latitude: 17.388, longitude: 78.487 },
      },
    ];

    const ranked = volunteers.map((v) => {
      const dist = haversineKm(incidentLocation, v.location);
      const skillMatches = requiredSkills.filter((s) =>
        v.skills.includes(s)
      ).length;
      const score =
        0.7 * Math.max(0, 1 - dist / radiusKm) +
        0.3 * (skillMatches / requiredSkills.length);
      return { ...v, dist, score };
    });

    ranked.sort((a, b) => b.score - a.score);

    // Sneha has 100% skill match (2/2) and is closer (0.33 km vs 1.14 km), so she ranks #1
    expect(ranked[0].id).toBe('vol-2');
    expect(ranked[0].score).toBeGreaterThan(ranked[1].score);
  });
});
