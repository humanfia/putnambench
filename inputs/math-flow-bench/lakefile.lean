import Lake
open Lake DSL

package math_flow_bench where

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.27.0"

@[default_target]
lean_lib MathFlowBench where
  globs := #[.submodules `MathFlowBench]
