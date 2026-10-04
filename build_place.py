"""Builds BecomeADeliveryDriver.rbxlx from src/ without needing Rojo."""
import pathlib, itertools
from xml.sax.saxutils import escape
n = itertools.count(1)
def src(path):
    return "<![CDATA[" + pathlib.Path(path).read_text().replace("]]>", "]]]]><![CDATA[>") + "]]>"
def item(cls, name, children="", source=None):
    s = f'<ProtectedString name="Source">{src(source)}</ProtectedString>' if source else ""
    return f'<Item class="{cls}" referent="RBX{next(n)}"><Properties><string name="Name">{escape(name)}</string>{s}</Properties>{children}</Item>'
def folder(name, kids): return item("Folder", name, "".join(kids))
S = "src/"
sss = item("ServerScriptService", "ServerScriptService", folder("Server", [
    item("Script", "Main", source=S+"server/Main.server.luau"),
    item("ModuleScript", "WorldBuilder", source=S+"server/WorldBuilder.luau"),
    item("ModuleScript", "CarSpawner", source=S+"server/CarSpawner.luau")]))
rs = item("ReplicatedStorage", "ReplicatedStorage", folder("Shared", [item("ModuleScript", "Config", source=S+"shared/Config.luau")]))
sp = item("StarterPlayer", "StarterPlayer", item("StarterPlayerScripts", "StarterPlayerScripts", folder("Client", [item("LocalScript", "Hud", source=S+"client/Hud.client.luau")])))
ws = item("Workspace", "Workspace")
out = '<roblox version="4">' + ws + rs + sss + sp + item("Lighting","Lighting") + item("Players","Players") + '</roblox>'
pathlib.Path("BecomeADeliveryDriver.rbxlx").write_text(out)
