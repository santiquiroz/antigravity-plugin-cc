# antigravity-plugin-cc

Delega tareas de programación desde [Claude Code](https://claude.com/claude-code)
a [Google Antigravity CLI](https://antigravity.google/docs/cli/overview) (`agy`)
en modo headless.

Claude Code sigue siendo el orquestador: escribe la lógica de dominio, define
el contrato de cada subtarea y revisa los diffs. Antigravity es un **segundo
carril con capacidades de frontera y cuota propia**: `agy` ejecuta
Gemini 3.1 Pro, Gemini 3.8 Flash, Claude Sonnet 4.6, Claude Opus 4.6 Thinking
y GPT-OSS 120B, seleccionables por llamada, y el delegado es agéntico: lee y
edita archivos y ejecuta comandos de build/test/git directamente en tu
repositorio. Úsalo cuando tu delegado principal de razonamiento (por ejemplo,
Codex) se quede sin créditos, cuando una tarea acotada merezca una segunda
opinión independiente, o con un modelo Flash para trabajo mecánico cuando tu
carril mecánico (por ejemplo, Copilot) se quede sin cuota.

Inspirado en la estructura de [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc)
y hermano de [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc),
[ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) y
[bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc).
**No afiliado con Google, OpenAI, GitHub ni Anthropic.**

> Read this in English: [README.md](README.md)

## Dónde se ubica en una cadena de delegación

| Nivel | Delegado | Ideal para |
|---|---|---|
| trivial | [ollama-plugin-cc](https://github.com/santiquiroz/ollama-plugin-cc) | transformaciones de texto one-shot en un modelo local pequeño |
| medio (local) | [bipolar-plugin-cc](https://github.com/santiquiroz/bipolar-plugin-cc) | tareas agénticas acotadas en un modelo local grande |
| mecánico | [copilot-plugin-cc](https://github.com/santiquiroz/copilot-plugin-cc) | boilerplate, renombres, especificaciones simples, limpieza |
| **frontera, segundo carril** | **antigravity-plugin-cc (este)** | fallback para Codex, segundas opiniones, trabajo mecánico en Flash cuando Copilot se queda sin cuota |
| frontera, principal | Codex / tu delegado principal de razonamiento | implementación cercana a la arquitectura, diagnóstico profundo |

Solo existen los carriles que instales; el plugin también funciona por sí solo.

## Requisitos

- Claude Code
- [Antigravity CLI](https://antigravity.google/docs/cli/install) ≥ **1.1.28**,
  con sesión iniciada una vez de forma interactiva (cuenta de Google: el plan
  gratuito tiene un tope semanal con ventanas de renovación de 5 horas; los
  planes Google AI Pro/Ultra lo aumentan).
  Windows: `irm https://antigravity.google/cli/install.ps1 | iex` —
  macOS/Linux: `curl -fsSL https://antigravity.google/cli/install.sh | bash`

## Instalación

En Claude Code:

```
/plugin marketplace add santiquiroz/antigravity-plugin-cc
/plugin install antigravity@antigravity-plugin-cc
```

Luego, una vez por máquina:

```
/antigravity:setup
```

Setup localiza el binario (PATH o los directorios conocidos de instalación),
verifica la versión mínima y la autenticación, fusiona las reglas de denegación
de las que depende este plugin en `~/.gemini/antigravity-cli/settings.json`
(preguntando primero), comprueba que surtan efecto con una prueba de
`git push --dry-run` y lista los modelos disponibles.

## Uso

Delegación explícita:

```
/antigravity:rescue diagnose why `npm test` fails in src/services/user-mapper.spec.ts and fix the spec
/antigravity:rescue --background --model gemini-3.8-flash-low generate boilerplate specs for src/services/user-mapper.ts (signatures pasted below) ...
/antigravity:rescue --model claude-opus-4-6-thinking --effort high second opinion: review the diff of HEAD for race conditions, report only, do not edit
```

Delegación proactiva: el agente `antigravity-rescue` se describe a sí mismo
para que Claude Code lo elija por su cuenta cuando coincidan los activadores.
Para integrarlo en tus propias reglas de delegación, pega el bloque de
[docs/claude-md-snippet.md](docs/claude-md-snippet.md) en tu `CLAUDE.md`.
La división multicarril, el patrón en paralelo, los límites de WIP y la
cadena de fallback por cuota se encuentran en
[docs/delegation-guide.md](docs/delegation-guide.md).

Elecciones de modelo que el subagente sugiere cuando indicas la clase de tarea:

| Clase de tarea | `--model` |
|---|---|
| mecánica (specs, renombres, boilerplate) | `gemini-3.8-flash-low` o `gemini-3.8-flash-medium` |
| diagnóstico, corrección del build, refactorización | `gemini-3.1-pro-high` |
| segunda opinión sobre un cambio complejo | `claude-opus-4-6-thinking` |
| no se pasa nada | valor predeterminado configurado en agy (`/model <name>` en una sesión interactiva) |

`agy models` imprime los slugs actuales; un slug desconocido termina con código 1 inmediatamente.

## Qué ejecuta realmente el reenviador

```bash
TASK=$(cat <<'EOF_TASK'
<your task, verbatim>

Constraints: work directly in this workspace following the instructions above. Do not invoke other AI CLIs (claude, codex, copilot, gemini, ollama). Do not commit, push, switch branches or delete files. If a command is denied by policy, stop and report it — do not look for another way to run it. Leave your changes in the working tree and end with a short list of the files you touched.
EOF_TASK
)
GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" agy -p "$TASK" \
  --add-dir "$PWD" \
  --dangerously-skip-permissions \
  --disable-slash-commands \
  --output-format text \
  --print-timeout 9m \
  [--model <slug>] [--effort low|medium|high] [--continue]
```

Una llamada en primer plano, con stdout devuelto textualmente, más cualquier
línea de stderr que comience con `jetski:` o `[agy]` (acciones con denegación
suave [soft-denied], salida parcial por print-timeout, errores fatales).

## Modelo de seguridad

Hechos sobre el modo headless de `agy` en los que se basa este plugin
(verificados en 1.1.28):

- El modo headless no puede solicitar confirmación interactiva. Cualquier
  herramienta que requiera aprobación es **denegada de forma suave
  (soft-denied)**: la ejecución continúa, termina con código 0, imprime un
  aviso `jetski:` en stderr y la incluye bajo `denied_actions` en la salida JSON.
  Sin `--dangerously-skip-permissions`, incluso `git status` es denegado, por
  lo que el reenviador siempre pasa ese flag.
- Las reglas de **`permissions.deny` configuradas por el usuario siguen teniendo
  prioridad bajo ese flag**
  (`Permission denied for command(...). Matches user-configured deny rule.`).
- Deny > Ask > Allow. Las reglas residen en
  `~/.gemini/antigravity-cli/settings.json` y son globales: no existe un flag de
  configuración por invocación.

Por lo tanto, `/antigravity:setup` fusiona esta lista de denegación
([docs/permissions.json](docs/permissions.json)):

| Regla | Bloquea |
|---|---|
| `command(regex:.*\bgit\s+push\b.*)` | hacer push a un estado compartido |
| `command(regex:.*\bgit\s+reset\b.*)` / `git\s+clean` | descartar trabajo |
| `command(regex:.*\brm\b.*)` / `rmdir` / `del` / `erase` / `rd` / `ri` / `Remove-Item` / `find … -delete` | eliminar archivos (variantes de POSIX, cmd y PowerShell) |
| `command(regex:.*\bsudo\b.*)` | escalamiento de privilegios |
| `write_file(.git/)` | editar metadatos del repositorio |

Las expresiones regulares usan `\b` para no capturar `transform`, `perform`,
`delete` ni términos similares, y están deliberadamente **sin anclar** para que
`xargs rm`, `git rm` y `sh -c "rm …"` también sean capturados. El costo es un
falso positivo cuando el nombre de un archivo es en sí mismo una palabra
bloqueada (`cat rm.txt`); el delegado entonces reporta la denegación y se
detiene, lo cual es la falla segura. El subagente **se niega a ejecutarse** si
el archivo de configuración no tiene un bloque `permissions.deny`.

Lo que esto **no** cubre — tenlo presente antes de delegar:

- La lista de denegación es global: esos comandos también se bloquean en tus
  propias sesiones interactivas de `agy`. Esto es intencional (son comandos
  destructivos o que afectan el estado compartido), y puedes editar el archivo,
  pero la seguridad del reenviador depende de ello.
- Bajo `--dangerously-skip-permissions`, la obtención web (`read_url`), el
  navegador y las herramientas MCP también se aprueban automáticamente. No
  delegues tareas que procesen contenido no confiable, y agrega `read_url(*)` /
  `mcp(*)` a `permissions.deny` si nunca quieres que el delegado esté en línea.
- Las denegaciones por patrón son del tipo best-effort, como cualquier lista de
  permisión/denegación en CLI: un comando escrito de forma inusual podría
  filtrarse. Revisa `git diff` antes de hacer commit; el delegado nunca hace
  commit.
- `--add-dir "$PWD"` registra el repositorio como el espacio de trabajo para
  que aplique el alcance de workspace propio de agy; el delegado se ejecuta con
  los mismos privilegios de tu usuario.

## Comportamientos conocidos de agy que este plugin mitiga

| Comportamiento (agy 1.1.28) | Manejo |
|---|---|
| Las ejecuciones headless no confían en el directorio actual; las lecturas sufren soft-deny | `--add-dir "$PWD"` en cada llamada |
| Una acción denegada suavemente produce un stdout vacío y un aviso en stderr | las líneas de stderr que comienzan con `jetski:` / `[agy]` se agregan al resultado |
| Una tarea que comienza con `/` se expande como un slash command | `--disable-slash-commands` |
| `--print-timeout` devuelve una salida parcial con exit 0 | fijado en 9m, por debajo del límite de la herramienta Bash, para que un turno largo se degrade en lugar de ser cancelado |
| El instalador puede dejar `agy` fuera del PATH (visto en Windows: binario en `%LOCALAPPDATA%\agy\bin` y `~/.gemini/bin`, ninguno en el PATH) | el subagente y setup resuelven esos directorios por sí mismos; setup ofrece `agy install` |
| `/usage` y `/credits` son solo interactivos | setup te indica dónde consultar; los errores de cuota se devuelven textualmente, nunca se reintentan |

## Qué incluye el plugin

| Componente | Propósito |
|---|---|
| `agents/antigravity-rescue.md` | Subagente reenviador ligero: una sola llamada a `agy -p`, salida devuelta textualmente |
| `/antigravity:rescue` | Delega una tarea explícitamente (`--background`, `--wait`, `--model`, `--effort`) |
| `/antigravity:setup` | Localiza el binario, versión mínima, prueba de autenticación, fusiona y verifica reglas de denegación, lista modelos |
| `docs/permissions.json` | Las reglas de denegación que fusiona setup |
| `docs/claude-md-snippet.md` | Bloque listo para pegar en CLAUDE.md |
| `docs/delegation-guide.md` | Guía de orquestación multicarril |

## Pendiente

- Variante de skill para Codex CLI (los plugins hermanos incluyen una).
- Un perfil de agente personalizado para agy
  (`~/.gemini/config/agents/<name>/agent.md`) para restringir herramientas por
  invocación en lugar de depender de la lista global de denegación.
  Issues y PRs son bienvenidos si has validado el frontmatter para ello.

## Licencia

[MIT](LICENSE)
