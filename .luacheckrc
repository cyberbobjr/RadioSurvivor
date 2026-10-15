-- Luacheck : Lua 5.1, le langage de Kahlua (Project Zomboid).
std = "lua51"
-- Les globales du jeu (Events, getText, ISButton…) et du mod (MTIR) sont trop
-- nombreuses pour être listées : on ne contrôle pas les globales.
global = false
-- Les signatures vanilla imposent souvent des paramètres inutilisés.
unused_args = false
codes = true
max_line_length = 130
exclude_files = { "source/**" }
