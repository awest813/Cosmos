# Dependency Recipes

Winetricks-style building blocks installed into a bottle on demand. Profiles
reference these by ID in their `dependencies:` list.

Planned recipe IDs (0.4–0.5):

- `vcrun2010`, `vcrun2013`, `vcrun2015`, ... — Visual C++ runtimes
- `d3dx9`, `d3dx10`, `d3dx11` — DirectX redistributable shims
- `dotnet48` — .NET Framework
- `corefonts` — common Windows fonts

Each recipe will eventually be a small declarative file describing what to
download, where to place it in the prefix, and how to register it. The format is
defined alongside the 0.5 repair engine.
</content>
