## 0.1.0

- First release: `Disintegrate` and `DisintegrateEffect`, backed by a fragment
  shader that runs through `ImageFilter.shader` on Impeller.
- Grains carry their own heading, speed and lifetime, so the surface scatters
  instead of sliding away with holes in it.
- `spread` gives the dust somewhere to travel beyond the child's own bounds.
- Falls back to an opacity fade on backends without shader filters.
