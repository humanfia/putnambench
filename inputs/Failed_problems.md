# PutnamBench-Full — problematic problems (verified 2026-07-07)

Verification: AXLE `verify_proof` on `lean-4.27.0` (`mathlib_options: true`), official statements from
`/scratch/gpfs/ARORA/juihui/goedel-prover-v3-train/datasets/putnam_bench/putnam_bench.jsonl` (672 problems; 679 files incl. 7 variants).
Cross-checked against compile-only run on the tiger3 kimina gateway (Lean 4.26.0).

**Passing: 574/672 (85.42%)** = 519 clean + 35 needing `native_decide` (`Lean.ofReduceBool`) + 20 solution-abbreviation
problems whose signatures def-eq match (AXLE `.match_1` bookkeeping artifact). Problematic: 98 problems, listed below.
Sections: [compile errors](#1-compile-errors-4) · [sorry](#2-incomplete-proof-1) · [signature mismatches](#3-signature-mismatches-93)

| Category | Count |
|---|---|
| Signature mismatch (compiles, statement ≠ official) | 93 |
| Compile error (all variants) | 4 |
| Contains `sorry` | 1 |
| **Total** | **98** |


## 1. Compile errors (4)

No variant compiles on Lean 4.27.0 (nor 4.26.0, except `putnam_1990_b1` which compiles on 4.26 only).

| Problem | File(s) | 4.26 compile | Error (first message) |
|---|---|---|---|
| putnam_1967_a5 | Putnam1967A5, Putnam1967A5_solve_again | fail/fail | -:41:16-41:46: error(lean.unknownIdentifier): Unknown identifier `brunn_minkowski_euclideanSpace` |
| putnam_1987_b6 | Putnam1987B6 | fail | -:25:21-25:22: error(lean.unknownIdentifier): Unknown identifier `F` Note: It is not possible to treat `F` as an implicitly bound variable here because the `autoImplicit` option is |
| putnam_1990_b1 | Putnam1990B1 | pass | -:7:81-7:82: error(lean.unknownIdentifier): Unknown identifier `x` Note: It is not possible to treat `x` as an implicitly bound variable here because the `autoImplicit` option is s |
| putnam_2022_a4 | Putnam2022A4 | fail | -:22:13-22:14: error(lean.unknownIdentifier): Unknown identifier `Ω` Note: It is not possible to treat `Ω` as an implicitly bound variable here because the `autoImplicit` option is |

## 2. Incomplete proof (1)

Proof compiles but contains `sorry`.

| Problem | File(s) | 4.26 compile | Error (first message) |
|---|---|---|---|
| putnam_2013_a5 | Putnam2013A5_solve_fail_again | fail | Declaration 'putnam_2013_a5' is incomplete (uses 'sorry' or has errors) |

## 3. Signature mismatches (93)

Proof compiles on 4.27.0, but the theorem statement fails AXLE's def-eq conformance check against the official statement in `putnam_bench.jsonl`. May reflect PutnamBench statement-vintage drift rather than an invalid proof — unaudited.

| Problem | File(s) | 4.26 compile | Error (first message) |
|---|---|---|---|
| putnam_1962_a2 | Putnam1962A2 | pass | Theorem 'putnam_1962_a2' does not match expected signature: expected type ∀ (P : Set ℝ → (ℝ → ℝ) → Prop), (∀ (s : Set ℝ) (f : ℝ → ℝ), P s f ↔ 0 ≤ f ∧ ∀ x ∈ s, ⨍ (t : ℝ) in Set.Ico  |
| putnam_1963_a3 | Putnam1963A3 | fail | Theorem 'putnam_1963_a3' does not match expected signature: expected type ∀ (P : ℕ → (ℝ → ℝ) → ℝ → ℝ), (P 0 = id ∧ ∀ (i : ℕ) (y : ℝ → ℝ), P (i + 1) y = P i fun x => x * deriv y x - |
| putnam_1965_b1 | Putnam1965B1 | pass | Theorem 'putnam_1965_b1' does not match expected signature: expected type Filter.Tendsto (fun n => ∫ (x : Fin (n + 1) → ℝ) in {x | ∀ (k : Fin (n + 1)), x k ∈ Set.Icc 0 1}, Real.cos |
| putnam_1965_b4 | Putnam1965B4 | pass | Theorem 'putnam_1965_b4' does not match expected signature: expected type ∀ (f u v : ℕ → ℝ → ℝ), (∀ n > 0, ∀ (x : ℝ), u n x = ∑ i ∈ Finset.Icc 0 (n / 2), ↑(n.choose (2 * i)) * x ^  |
| putnam_1968_a6 | Putnam1968A6 | pass | Theorem 'putnam_1968_a6' does not match expected signature: expected type {P | P.natDegree ≥ 1 ∧ (∀ k ∈ Set.Icc 0 P.natDegree, P.coeff k = 1 ∨ P.coeff k = -1) ∧ ∀ (z : ℂ), Polynomi |
| putnam_1969_a1 | Putnam1969A1 | pass | Theorem 'putnam_1969_a1' does not match expected signature: expected type {x | ∃ f, {z | ∃ x, (MvPolynomial.eval x) f = z} = x} = {x | ∃ x_1, {x_1} = x} ∪ {x | ∃ x_1, Set.Ici x_1 = |
| putnam_1970_a3 | Putnam1970A3 | pass | Theorem 'putnam_1970_a3' does not match expected signature: expected type ∀ (L : ℕ → ℕ), (∀ (n : ℕ), L n ≤ (Nat.digits 10 n).length ∧ (∀ k < L n, (Nat.digits 10 n)[k]! = (Nat.digit |
| putnam_1970_b1 | Putnam1970B1 | pass | Theorem 'putnam_1970_b1' does not match expected signature: expected type Filter.Tendsto (fun n => 1 / ↑n ^ 4 * ∏ i ∈ Finset.Icc 1 (2 * n), (↑n ^ 2 + ↑i ^ 2) ^ (1 / ↑n)) Filter.atT |
| putnam_1971_b2 | Putnam1971B2 | pass | Theorem 'putnam_1971_b2' does not match expected signature: expected type ∀ (S : Set ℝ), S = Set.univ \ {0, 1} → ∀ (P : (ℝ → ℝ) → Prop), (P = fun F => ∀ x ∈ S, F x + F ((x - 1) / x |
| putnam_1973_a2 | Putnam1973A2 | pass | Theorem 'putnam_1973_a2' does not match expected signature: expected type ∀ (L : List ℝ) (hL : L.length = 8 ∧ ∀ (i : Fin L.length), L[i] = 1 ∨ L[i] = -1) (pluses : ℕ), pluses = {i  |
| putnam_1974_b6 | Putnam1974B6 | pass | Theorem 'putnam_1974_b6' does not match expected signature: expected type ∀ (n : ℤ), n = 1000 → ∀ (count0 count1 count2 : ℕ), count0 = {S | S ⊆ Finset.Icc 1 n ∧ S.card ≡ 0 [MOD 3]} |
| putnam_1975_b3 | Putnam1975B3 | pass | Theorem 'putnam_1975_b3' does not match expected signature: expected type ∀ k > 0, (∀ (a : Multiset ℝ), (∀ i ∈ a, i > 0) ∧ a.card ≥ k → a.esymm k / a.esymm 1 ^ k ≤ (fun k => 1 / ↑k |
| putnam_1976_b1 | Putnam1976B1 | fail | Theorem 'putnam_1976_b1' does not match expected signature: expected type Filter.Tendsto (fun n => 1 / ↑n * ↑(∑ k ∈ Finset.Icc 1 ↑n, (⌊2 * ↑n / k⌋ - 2 * ⌊↑n / k⌋))) Filter.atTop (𝓝 |
| putnam_1976_b2 | Putnam1976B2 | pass | Theorem 'putnam_1976_b2' does not match expected signature: expected type ∀ (G : Type u_1) [inst : Group G] (A B : G) (word : List (ℤ × ℤ) → G), (word = fun w => (List.map (fun t = |
| putnam_1977_a4 | Putnam1977A4 | pass | Theorem 'putnam_1977_a4' does not match expected signature: expected type ∀ x ∈ Set.Ioo 0 1, RatFunc.eval (RingHom.id ℝ) x (RatFunc.X / (1 - RatFunc.X)) = ∑' (n : ℕ), x ^ 2 ^ n / ( |
| putnam_1977_b1 | Putnam1977B1 | pass | Theorem 'putnam_1977_b1' does not match expected signature: expected type Filter.Tendsto (fun N => ∏ n ∈ Finset.Icc 2 N, (↑n ^ 3 - 1) / (↑n ^ 3 + 1)) Filter.atTop (𝓝 (2 / 3)), got  |
| putnam_1978_b5 | Putnam1978B5 | pass | Theorem 'putnam_1978_b5' does not match expected signature: expected type ∀ (S : Set ℝ[X]), S = {p | p.degree = 4 ∧ ∀ x ∈ Set.Icc (-1) 1, Polynomial.eval x p ∈ Set.Icc 0 1} → 4 * P |
| putnam_1979_a1 | Putnam1979A1 | pass | Theorem 'putnam_1979_a1' does not match expected signature: expected type ∀ (P : Multiset ℕ → Prop), (∀ (a : Multiset ℕ), P a ↔ a.card > 0 ∧ (∀ i ∈ a, i > 0) ∧ a.sum = 1979) → P (M |
| putnam_1979_b3 | Putnam1979B3 | pass | Theorem 'putnam_1979_b3' does not match expected signature: expected type ∀ (F : Type u_1) [inst : Field F] [inst_1 : Fintype F] (n : ℕ), n = Fintype.card F → Odd n → ∀ (b c : F) ( |
| putnam_1981_a1 | Putnam1981A1 | pass | Theorem 'putnam_1981_a1' does not match expected signature: expected type ∀ (P : ℕ → ℕ → Prop), (∀ (n k : ℕ), P n k ↔ 5 ^ k ∣ ∏ m ∈ Finset.Icc 1 n, ↑m ^ m) → ∀ (E : ℕ → ℕ), (∀ n ∈  |
| putnam_1981_b1 | Putnam1981B1 | pass | Theorem 'putnam_1981_b1' does not match expected signature: expected type ∀ (f : ℕ → ℝ), (f = fun n => 1 / ↑n ^ 5 * ∑ h ∈ Finset.Icc 1 n, ∑ k ∈ Finset.Icc 1 n, (5 * ↑h ^ 4 - 18 * ↑ |
| putnam_1982_a3 | Putnam1982A3 | fail | Theorem 'putnam_1982_a3' does not match expected signature: expected type Filter.Tendsto (fun t => ∫ (x : ℝ) in 0..t, (Real.arctan (π * x) - Real.arctan x) / x) Filter.atTop (𝓝 (π  |
| putnam_1983_a6 | Putnam1983A6 | pass | Theorem 'putnam_1983_a6' does not match expected signature: expected type ∀ (F : ℝ → ℝ), (F = fun a => a ^ 4 / rexp (a ^ 3) * ∫ (x : ℝ) in 0..a, ∫ (y : ℝ) in 0..a - x, rexp (x ^ 3  |
| putnam_1983_b5 | Putnam1983B5 | fail | Theorem 'putnam_1983_b5' does not match expected signature: expected type ∀ (dist_fun : ℝ → ℝ), (dist_fun = fun x => min (x - ↑⌊x⌋) (↑⌈x⌉ - x)) → Filter.Tendsto (fun N => ∏ n ∈ Fin |
| putnam_1984_a2 | Putnam1984A2 | pass | Theorem 'putnam_1984_a2' does not match expected signature: expected type ∑' (k : ↑(Set.Ici 1)), 6 ^ ↑k / ((3 ^ (↑k + 1) - 2 ^ (↑k + 1)) * (3 ^ ↑k - 2 ^ ↑k)) = 2, got ∑' (k : ↑(Set |
| putnam_1984_a3 | Putnam1984A3 | pass | Theorem 'putnam_1984_a3' does not match expected signature: expected type ∀ (n : ℕ) (a b : ℝ) (Mn : ℝ → Matrix (Fin (2 * n)) (Fin (2 * n)) ℝ) (polyabn : Fin 3 → ℝ), n > 0 → a ≠ b → |
| putnam_1984_b1 | Putnam1984B1 | pass | Theorem 'putnam_1984_b1' does not match expected signature: expected type ∀ (f : ℕ → ℤ), (∀ n > 0, f n = ∑ i, ↑(↑i)!) → match (Polynomial.X + 3, -Polynomial.X - 2) with | (P, Q) => |
| putnam_1984_b5 | Putnam1984B5 | fail | Theorem 'putnam_1984_b5' does not match expected signature: expected type ∀ m > 0, ∀ (d : ℕ → ℕ) (sumbits : List ℕ → ℕ), (∀ (bits : List ℕ), sumbits bits = ∑ i, bits[i]) → (∀ (k :  |
| putnam_1985_a3 | Putnam1985A3 | pass | Theorem 'putnam_1985_a3' does not match expected signature: expected type ∀ (d : ℝ) (a : ℕ → ℕ → ℝ), (∀ (m : ℕ), a m 0 = d / 2 ^ m) → (∀ (m j : ℕ), a m (j + 1) = a m j ^ 2 + 2 * a  |
| putnam_1985_a4 | Putnam1985A4 | pass | Theorem 'putnam_1985_a4' does not match expected signature: expected type ∀ (a : ℕ → ℕ), a 1 = 3 → (∀ i ≥ 1, a (i + 1) = 3 ^ a i) → {k | ∀ (N : ℕ), ∃ i ≥ N, a i % 100 = ↑k} = {87}, |
| putnam_1985_b1 | Putnam1985B1 | pass | Theorem 'putnam_1985_b1' does not match expected signature: expected type ∀ (p : (Fin 5 → ℤ) → ℝ[X]), (p = fun m => ∏ i, (Polynomial.X - ↑(m i))) → ∀ (numnzcoeff : ℝ[X] → ℕ), (numn |
| putnam_1986_a2 | Putnam1986A2 | pass | Theorem 'putnam_1986_a2' does not match expected signature: expected type ⌊10 ^ 20000 / (10 ^ 100 + 3)⌋₊ % 10 = 3, got ⌊10 ^ 20000 / (10 ^ 100 + 3)⌋₊ % 10 = putnam_1986_a2_solution |
| putnam_1986_a6 | Putnam1986A6 | pass | Theorem 'putnam_1986_a6' does not match expected signature: expected type ∀ n > 0, ∀ (a : ℕ → ℝ) (b : ℕ → ℕ), (∀ i ∈ Finset.Icc 1 n, b i > 0) → (∀ i ∈ Finset.Icc 1 n, ∀ j ∈ Finset. |
| putnam_1989_b3 | Putnam1989B3 | fail | Theorem 'putnam_1989_b3' does not match expected signature: expected type ∀ (f : ℝ → ℝ), Differentiable ℝ f → (∀ x > 0, deriv f x = -3 * f x + 6 * f (2 * x)) → (∀ x ≥ 0, |f x| ≤ Re |
| putnam_1990_a6 | Putnam1990A6 | pass | Theorem 'putnam_1990_a6' does not match expected signature: expected type {x | match x with | (S, T) => (∀ s ∈ S, T.card < ↑s) ∧ ∀ t ∈ T, S.card < ↑t}.card = 17711, got {x | match  |
| putnam_1991_a6 | Putnam1991A6 | fail | Theorem 'putnam_1991_a6' does not match expected signature: expected type ∀ (nabsum : ℕ → ℕ × (ℕ → ℕ) → Prop) (agt bge bg1 bg2 : ℕ × (ℕ → ℕ) → Prop) (A g B : ℕ → ℕ), (∀ n ≥ 1, ∀ (a |
| putnam_1991_b5 | Putnam1991B5 | pass | Theorem 'putnam_1991_b5' does not match expected signature: expected type ∀ (p : ℕ), Odd p → Prime p → ({z | ∃ x, z = x ^ 2} ∩ {z | ∃ y, z = y ^ 2 + 1}).encard = ↑((fun p => ⌈↑p /  |
| putnam_1991_b6 | Putnam1991B6 | pass | Theorem 'putnam_1991_b6' does not match expected signature: expected type ∀ (a b : ℝ), a > 0 ∧ b > 0 → IsGreatest {c | ∀ (u : ℝ), 0 < |u| ∧ |u| ≤ c → ∀ x ∈ Set.Ioo 0 1, a ^ x * b ^ |
| putnam_1992_a2 | Putnam1992A2 | pass | Theorem 'putnam_1992_a2' does not match expected signature: expected type ∀ (C : ℝ → ℝ), (C = fun α => taylorCoeffWithin (fun x => (1 + x) ^ α) 1992 Set.univ 0) → ∫ (y : ℝ) in 0..1 |
| putnam_1993_b1 | Putnam1993B1 | pass | Theorem 'putnam_1993_b1' does not match expected signature: expected type IsLeast {n | 0 < n ∧ ∀ m ∈ Set.Ioo 0 1993, ∃ k, ↑m / 1993 < ↑k / ↑n ∧ ↑k / ↑n < (↑m + 1) / 1994} 3987, got |
| putnam_1996_a6 | Putnam1996A6 | pass | Theorem 'putnam_1996_a6' does not match expected signature: expected type ∀ (c : ℝ) (f : ℝ → ℝ), c > 0 → ((Continuous f ∧ ∀ (x : ℝ), f x = f (x ^ 2 + c)) ↔ f ∈ (fun c => if c ≤ 1 / |
| putnam_1996_b3 | Putnam1996B3 | fail | Theorem 'putnam_1996_b3' does not match expected signature: expected type ∀ n ≥ 2, IsGreatest {k | ∃ x, x '' ↑(Finset.range n) = Set.Icc 1 ↑n ∧ ∑ i, x ↑i * x ((↑i + 1) % n) = k} ↑( |
| putnam_1997_a3 | Putnam1997A3 | fail | Theorem 'putnam_1997_a3' does not match expected signature: expected type ∀ (series1 series2 : ℝ → ℝ), (series1 = fun x => ∑' (n : ℕ), (-1) ^ n * x ^ (2 * n + 1) / ∏ i, 2 * (↑↑i +  |
| putnam_1998_b5 | Putnam1998B5 | pass | Theorem 'putnam_1998_b5' does not match expected signature: expected type ∀ (N : ℕ), N = ∑ i ∈ Finset.range 1998, 10 ^ i → 1 = ⌊10 ^ 1000 * √↑N⌋₊ % 10, got ∀ (N : ℕ), N = ∑ i ∈ Fin |
| putnam_1999_a4 | Putnam1999A4 | pass | Theorem 'putnam_1999_a4' does not match expected signature: expected type Filter.Tendsto (fun i => ∑ m ∈ Finset.range i, ∑' (n : ℕ), (↑m + 1) ^ 2 * (↑n + 1) / (3 ^ (m + 1) * ((↑n + |
| putnam_1999_b3 | Putnam1999B3 | pass | Theorem 'putnam_1999_b3' does not match expected signature: expected type ∀ (A : Set (ℝ × ℝ)), A = {xy | 0 ≤ xy.1 ∧ xy.1 < 1 ∧ 0 ≤ xy.2 ∧ xy.2 < 1} → ∀ (S : ℝ → ℝ → ℝ), (S = fun x  |
| putnam_2000_b3 | Putnam2000B3 | fail | Theorem 'putnam_2000_b3' does not match expected signature: expected type ∀ (N : ℕ) (hN : N > 0) (a : ↑(Set.Icc 1 N) → ℝ) (f : ℝ → ℝ) (mult : (ℝ → ℝ) → ℝ → ℕ) (M : ℕ → ℕ), a ⟨N, Eq |
| putnam_2001_b2 | Putnam2001B2 | pass | Theorem 'putnam_2001_b2' does not match expected signature: expected type ∀ (x y : ℝ), x ≠ 0 → y ≠ 0 → ∀ (eq1 eq2 : Prop), (eq1 ↔ 1 / x + 1 / (2 * y) = (x ^ 2 + 3 * y ^ 2) * (3 * x |
| putnam_2004_b5 | Putnam2004B5 | pass | Theorem 'putnam_2004_b5' does not match expected signature: expected type ∀ (xprod : ℝ → ℝ), (∀ x ∈ Set.Ioo 0 1, Filter.Tendsto (fun N => ∏ n ∈ Finset.range N, ((1 + x ^ (n + 1)) / |
| putnam_2005_a2 | Putnam2005A2, Putnam2005A2_solve_fail_again | pass/fail | Theorem 'putnam_2005_a2' does not match expected signature: expected type ∀ n > 0, ∀ (S : Set (ℤ × ℤ)) (unit : ℤ × ℤ → ℤ × ℤ → Prop) (rooktour : (ℕ → ℤ × ℤ) → Prop), S = (Set.Icc 1 |
| putnam_2005_a5 | Putnam2005A5 | pass | Theorem 'putnam_2005_a5' does not match expected signature: expected type ∫ (x : ℝ) in 0..1, Real.log (x + 1) / (x ^ 2 + 1) = Real.pi * Real.log 2 / 8, got ∫ (x : ℝ) in 0..1, Real. |
| putnam_2005_b1 | Putnam2005B1 | pass | Theorem 'putnam_2005_b1' does not match expected signature: expected type (MvPolynomial.X 1 - 2 * MvPolynomial.X 0) * (MvPolynomial.X 1 - 2 * MvPolynomial.X 0 - 1) ≠ 0 ∧ ∀ (a : ℝ), |
| putnam_2005_b2 | Putnam2005B2 | pass | Theorem 'putnam_2005_b2' does not match expected signature: expected type {(n, k) | n > 0 ∧ (∀ i ∈ Finset.range n, k i > 0) ∧ ∑ i ∈ Finset.range n, k i = 5 * ↑n - 4 ∧ ∑ i, 1 / ↑(k  |
| putnam_2006_a5 | Putnam2006A5 | fail | Theorem 'putnam_2006_a5' does not match expected signature: expected type ∀ (n : ℕ) (theta : ℝ) (a : ↑(Set.Icc 1 n) → ℝ), Odd n → Irrational (theta / Real.pi) → (∀ (k : ↑(Set.Icc 1 |
| putnam_2006_b6 | Putnam2006B6 | pass | Theorem 'putnam_2006_b6' does not match expected signature: expected type ∀ k > 1, ∀ (a : ℕ → ℝ), a 0 > 0 → (∀ (n : ℕ), a (n + 1) = a n + 1 / a n ^ (1 / ↑k)) → Filter.Tendsto (fun  |
| putnam_2007_b3 | Putnam2007B3 | pass | Theorem 'putnam_2007_b3' does not match expected signature: expected type ∀ (x : ℕ → ℝ), x 0 = 1 → (∀ (n : ℕ), x (n + 1) = 3 * x n + ↑⌊x n * √5⌋) → x 2007 = 2 ^ 2006 / √5 * (((1 +  |
| putnam_2008_b2 | Putnam2008B2 | pass | Theorem 'putnam_2008_b2' does not match expected signature: expected type ∀ (F : ℕ → ℝ → ℝ), (∀ (x : ℝ), F 0 x = Real.log x) → (∀ (n : ℕ), ∀ x > 0, F (n + 1) x = ∫ (t : ℝ) in Set.I |
| putnam_2009_a2 | Putnam2009A2 | pass | Theorem 'putnam_2009_a2' does not match expected signature: expected type ∀ (f g h : ℝ → ℝ) (a b : ℝ), 0 ∈ Set.Ioo a b → DifferentiableOn ℝ f (Set.Ioo a b) ∧ DifferentiableOn ℝ g ( |
| putnam_2009_a3 | Putnam2009A3 | pass | Theorem 'putnam_2009_a3' does not match expected signature: expected type ∀ (cos_matrix : (n : ℕ) → Matrix (Fin n) (Fin n) ℝ), (∀ (n : ℕ) (i j : Fin n), cos_matrix n i j = Real.cos |
| putnam_2009_a5 | Putnam2009A5 | fail | Theorem 'putnam_2009_a5' does not match expected signature: expected type (∃ G x x_1, ∏ g, orderOf g = 2 ^ 2009) ↔ False, got (∃ G x x_1, ∏ g, orderOf g = 2 ^ 2009) ↔ putnam_2009_a |
| putnam_2010_a1 | Putnam2010A1 | pass | Theorem 'putnam_2010_a1' does not match expected signature: expected type ∀ (n : ℕ) (kboxes : ℕ → Prop), n > 0 → (∀ (k : ℕ), kboxes k = ∃ boxes, ∀ (i j : Fin k), ∑ x with boxes x = |
| putnam_2010_b2 | Putnam2010B2 | fail | Theorem 'putnam_2010_b2' does not match expected signature: expected type ∀ (ABCintcoords ABCintdists ABCall : EuclideanSpace ℝ (Fin 2) → EuclideanSpace ℝ (Fin 2) → EuclideanSpace  |
| putnam_2011_a1 | Putnam2011A1 | pass | Theorem 'putnam_2011_a1' does not match expected signature: expected type ∀ (IsSpiral : List (Fin 2 → ℤ) → Prop), (∀ (P : List (Fin 2 → ℤ)), IsSpiral P ↔ P.length ≥ 3 ∧ P[0]! = 0 ∧ |
| putnam_2011_a2 | Putnam2011A2 | pass | Theorem 'putnam_2011_a2' does not match expected signature: expected type ∀ (a b : ℕ → ℝ), (∀ (n : ℕ), a n > 0 ∧ b n > 0) → a 0 = 1 ∧ b 0 = 1 → (∀ n ≥ 1, b n = b (n - 1) * a n - 2) |
| putnam_2011_a3 | Putnam2011A3 | pass | Theorem 'putnam_2011_a3' does not match expected signature: expected type (-1, 2 / Real.pi).2 > 0 ∧ Filter.Tendsto (fun r => (r ^ (-1, 2 / Real.pi).1 * ∫ (x : ℝ) in Set.Ioo 0 (Real |
| putnam_2013_a2 | Putnam2013A2 | pass | Theorem 'putnam_2013_a2' does not match expected signature: expected type ∀ (S : Set ℤ), S = {n | n > 0 ∧ ¬∃ m, m ^ 2 = n} → ∀ (P : ℤ → List ℤ → Prop), (∀ (n : ℤ) (a : List ℤ), P n |
| putnam_2013_b1 | Putnam2013B1 | pass | Theorem 'putnam_2013_b1' does not match expected signature: expected type ∀ (c : ℕ → ℤ), c 1 = 1 → (∀ n > 0, c (2 * n) = c n) → (∀ n > 0, c (2 * n + 1) = (-1) ^ n * c n) → ∑ n, c ↑ |
| putnam_2014_a3 | Putnam2014A3 | pass | Theorem 'putnam_2014_a3' does not match expected signature: expected type ∀ (a : ℕ → ℝ), a 0 = 5 / 2 → (∀ k ≥ 1, a k = a (k - 1) ^ 2 - 2) → Filter.Tendsto (fun n => ∏ k ∈ Finset.ra |
| putnam_2014_b2 | Putnam2014B2 | pass | Theorem 'putnam_2014_b2' does not match expected signature: expected type IsGreatest {t | ∃ f, (∀ (x : ↑(Set.Icc 1 3)), -1 ≤ f ↑x ∧ f ↑x ≤ 1) ∧ ∫ (x : ℝ) in Set.Ioo 1 3, f x = 0 ∧  |
| putnam_2015_a3 | Putnam2015A3 | pass | Theorem 'putnam_2015_a3' does not match expected signature: expected type Complex.log (∏ a, ∏ b, (1 + Complex.exp (2 * ↑Real.pi * Complex.I * (↑↑a + 1) * (↑↑b + 1) / 2015))) / Comp |
| putnam_2015_b3 | Putnam2015B3 | pass | Theorem 'putnam_2015_b3' does not match expected signature: expected type ∀ (M : Matrix (Fin 2) (Fin 2) ℝ) (S : Set (Matrix (Fin 2) (Fin 2) ℝ)), S = {M' | M' 0 1 - M' 0 0 = M' 1 0  |
| putnam_2015_b6 | Putnam2015B6 | pass | Theorem 'putnam_2015_b6' does not match expected signature: expected type ∀ (A : ℕ → ℕ), (∀ k > 0, ↑(A k) = {j | Odd j ∧ j ∣ k ∧ ↑j < √(2 * ↑k)}.encard) → Filter.Tendsto (fun K =>  |
| putnam_2016_a2 | Putnam2016A2 | pass | Theorem 'putnam_2016_a2' does not match expected signature: expected type ∀ (M : ℕ → ℕ), (∀ n > 0, IsGreatest {m | 0 < m ∧ (m - 1).choose n < m.choose (n - 1)} (M n)) → Filter.Tend |
| putnam_2017_b3 | Putnam2017B3 | fail | Theorem 'putnam_2017_b3' does not match expected signature: expected type ∀ (f : ℝ → ℝ) (c : ℕ → ℝ), (∀ (n : ℕ), c n = 0 ∨ c n = 1) → (∀ (x : ℝ), f x = ∑' (n : ℕ), c n * x ^ n) → f |
| putnam_2017_b4 | Putnam2017B4 | fail | Theorem 'putnam_2017_b4' does not match expected signature: expected type ∑' (k : ℕ), (3 * Real.log (4 * ↑k + 2) / (4 * ↑k + 2) - Real.log (4 * ↑k + 3) / (4 * ↑k + 3) - Real.log (4 |
| putnam_2017_b6 | Putnam2017B6 | system-error | Theorem 'putnam_2017_b6' does not match expected signature: expected type ∀ (S : Finset (↥(Finset.range 64) → ↥(Finset.Icc 1 2017))), (∀ (x : ↥(Finset.range 64) → ↥(Finset.Icc 1 20 |
| putnam_2019_a3 | Putnam2019A3 | pass | Theorem 'putnam_2019_a3' does not match expected signature: expected type ∀ (v : Polynomial ℂ → Prop), (v = fun b => b.degree = 2019 ∧ 1 ≤ (b.coeff 0).re ∧ (b.coeff 2019).re ≤ 2019 |
| putnam_2019_b2 | Putnam2019B2 | pass | Theorem 'putnam_2019_b2' does not match expected signature: expected type ∀ (a : ℕ → ℝ), (a = fun n => ∑ k, Real.sin ((2 * ↑↑k - 1) * Real.pi / (2 * ↑n)) / (Real.cos ((↑↑k - 1) * R |
| putnam_2019_b4 | Putnam2019B4 | fail | Theorem 'putnam_2019_b4' does not match expected signature: expected type ∀ (f : (Fin 2 → ℝ) → ℝ) (vec : ℝ → ℝ → Fin 2 → ℝ), ContDiff ℝ 2 f → (∀ (x y : ℝ), vec x y 0 = x ∧ vec x y  |
| putnam_2020_a5 | Putnam2020A5 | pass | Theorem 'putnam_2020_a5' does not match expected signature: expected type ∀ (a : ℤ → ℕ), (a = fun n => {S | (∀ k ∈ S, k > 0) ∧ ↑(∑ k, Nat.fib ↑k) = n}.ncard) → IsGreatest {n | a n  |
| putnam_2021_a2 | Putnam2021A2 | pass | Theorem 'putnam_2021_a2' does not match expected signature: expected type ∀ (g : ℝ → ℝ), (∀ x > 0, Filter.Tendsto (fun r => ((x + 1) ^ (r + 1) - x ^ (r + 1)) ^ (1 / r)) (𝓝[>] 0) (𝓝 |
| putnam_2021_a3 | Putnam2021A3 | fail | Theorem 'putnam_2021_a3' does not match expected signature: expected type ∀ (N : ℕ) (Nsphere : Set (EuclideanSpace ℝ (Fin 3))), Nsphere = {p | p.ofLp 0 ^ 2 + p.ofLp 1 ^ 2 + p.ofLp  |
| putnam_2021_a4 | Putnam2021A4 | fail | Theorem 'putnam_2021_a4' does not match expected signature: expected type ∀ (S : ℝ → Set (EuclideanSpace ℝ (Fin 2))), (S = fun R => Metric.ball 0 R) → ∀ (I : ℝ → ℝ), (I = fun R =>  |
| putnam_2022_a5 | Putnam2022A5 | pass | Theorem 'putnam_2022_a5' does not match expected signature: expected type ∀ (IsValidMove : Set (Fin 2022) → Set (Fin 2022) → Prop), (∀ (x y : Set (Fin 2022)), IsValidMove x y ↔ (x  |
| putnam_2022_a6 | Putnam2022A6 | pass | Theorem 'putnam_2022_a6' does not match expected signature: expected type ∀ (n : ℕ), 0 < n → IsGreatest {m | ∃ x, StrictMono x ∧ -1 < x 1 ∧ x (2 * n) < 1 ∧ ∀ k ∈ Set.Icc 1 m, ∑ i ∈ |
| putnam_2023_a1 | Putnam2023A1 | fail | Theorem 'putnam_2023_a1' does not match expected signature: expected type ∀ (f : ℕ → ℝ → ℝ), (∀ n > 0, f n = fun x => ∏ i ∈ Finset.Icc 1 n, Real.cos (↑i * x)) → IsLeast {n | 0 < n  |
| putnam_2023_a2 | Putnam2023A2 | pass | Theorem 'putnam_2023_a2' does not match expected signature: expected type ∀ (n : ℕ), n > 0 ∧ Even n → ∀ (p : Polynomial ℝ), p.Monic ∧ p.degree = 2 * ↑n → ∀ (S : Set ℝ), S = {x | ∃  |
| putnam_2023_a5 | Putnam2023A5 | fail | Theorem 'putnam_2023_a5' does not match expected signature: expected type {z | ∑ k ∈ Finset.Icc 0 (3 ^ 1010 - 1), (-2) ^ num_ones (Nat.digits 3 k) * (z + ↑k) ^ 2023 = 0} = {-(3 ^ 1 |
| putnam_2024_a3 | Putnam2024A3 | pass | Theorem 'putnam_2024_a3' does not match expected signature: expected type ∀ (S : Set (ℕ × ℕ → ℕ)), S = {T | Set.BijOn T (↑(Finset.Icc 1 3) ×ˢ ↑(Finset.Icc 1 2024)) ↑(Finset.Icc 1 6 |
| putnam_2024_b1 | Putnam2024B1 | pass | Theorem 'putnam_2024_b1' does not match expected signature: expected type ∀ (grid : (n : ℕ) → ℕ → Fin n → Fin n → ℤ), (∀ (n k : ℕ) (i j : Fin n), grid n k i j = ↑↑i.succ + ↑↑j.succ |
| putnam_2024_b4 | Putnam2024B4 | pass | Theorem 'putnam_2024_b4' does not match expected signature: expected type ∀ {Ω : Type u_1} [inst : MeasureTheory.MeasureSpace Ω] [MeasureTheory.IsProbabilityMeasure ℙ] (m a : ℕ → ℕ |
| putnam_2025_a4 | Putnam2025A4 | pass | Theorem 'putnam_2025_a4' does not match expected signature: expected type IsLeast {k | ∃ A, ∀ (i j : Fin 2025), i ≤ j → (A i * A j = A j * A i ↔ ↑j - ↑i ∈ {0, 1, 2024})} 3, got IsL |
| putnam_2025_b6 | Putnam2025B6 | pass | Theorem 'putnam_2025_b6' does not match expected signature: expected type IsGreatest {r | ∃ g, (∀ (n : ℕ), 0 < n → 0 < g n) ∧ ∀ (n : ℕ), 0 < n → ↑(g (g n)) ^ r ≤ ↑(g (n + 1)) - ↑(g |
