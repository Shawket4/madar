//! A small deterministic PRNG (SplitMix64): every simulated decision comes from
//! a seed, so a failing run replays exactly.

#[derive(Clone, Debug)]
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng(seed ^ 0x9E37_79B9_7F4A_7C15)
    }

    /// An independent stream derived from this seed and a label.
    pub fn fork(&self, label: u64) -> Rng {
        let mut r = Rng(self.0 ^ label.wrapping_mul(0xD1B5_4A32_D192_ED03));
        r.next_u64();
        r
    }

    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in `[0, n)` (`n > 0`).
    pub fn below(&mut self, n: u64) -> u64 {
        self.next_u64() % n.max(1)
    }

    /// Uniform in `[lo, hi]`.
    pub fn range(&mut self, lo: i64, hi: i64) -> i64 {
        lo + self.below((hi - lo + 1).max(1) as u64) as i64
    }

    /// `true` with probability `p`.
    pub fn chance(&mut self, p: f64) -> bool {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64 <= p
    }

    pub fn pick<'a, T>(&mut self, items: &'a [T]) -> Option<&'a T> {
        if items.is_empty() {
            None
        } else {
            Some(&items[self.below(items.len() as u64) as usize])
        }
    }

    /// A UUID from the stream (deterministic ids).
    pub fn uuid(&mut self) -> String {
        let hi = self.next_u64();
        let lo = self.next_u64();
        let mut b = [0u8; 16];
        b[..8].copy_from_slice(&hi.to_be_bytes());
        b[8..].copy_from_slice(&lo.to_be_bytes());
        uuid::Builder::from_random_bytes(b).into_uuid().to_string()
    }
}
