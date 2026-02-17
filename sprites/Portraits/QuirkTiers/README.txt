ZombieMECHA Portrait Quirk Tiers (64x64)

Files:
- *_q0.png : no quirks (clean)
- *_q1.png : 1 quirk (modified)
- *_q2.png : 2 quirks (unstable)
- *_q3.png : 3 quirks (anomalous)

Suggested usage (Option A):
- Use base portrait path as *_q0.png
- Swap to *_q1/_q2/_q3 based on quirk count (0..3)

Option B shader:
Use your portrait TextureRect with a ShaderMaterial and set quirk_intensity = qcount/3.0
(Shader snippet provided in chat.)