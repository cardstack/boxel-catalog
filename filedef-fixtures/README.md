# FileDef fixtures

Sample files linked as `fileExamples` from the FileDef Specs in `Spec/`. Each file is the moderate tier of the base realm's file-format fixture set: a compact, normally authored file that exercises the format's header reader without being a stress test.

| File                            | Linked from           | Source                                                                                                                                         | License                                                                                               |
| ------------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `samples/gltf-moderate.gltf`    | `Spec/gltf-model-def` | Textured box from [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets), generator `COLLADA2GLTF`                   | CC0 1.0 (Khronos sample asset)                                                                        |
| `samples/glb-moderate.glb`      | `Spec/glb-model-def`  | Same scene as the `.gltf` above in the binary container                                                                                        | CC0 1.0 (Khronos sample asset)                                                                        |
| `samples/three-mf-moderate.3mf` | `Spec/three-mf-def`   | [Heart Gears](https://github.com/3MFConsortium/3mf-samples/blob/master/examples/core/heartgears.3mf) from the 3MF Consortium sample repository | BSD-2-Clause (repository); the model carries embedded CC BY-SA terms and attribution to Emmett Lalish |

Only `specType: 'file'` Specs link fixtures. The Spec template renders `fileExamples` for that spec type alone, and the tracker's quality rubric counts them only for FileDefs, so a component Spec gains nothing from a file link.
