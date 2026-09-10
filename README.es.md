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
/antigravity:rescue --model claude-opus-4-6-thinking second opinion: review the diff of HEAD for race conditions, report only, do not edit
```

### Flags y límites

Coloca primero los flags y después el texto de la tarea (el comando los
reconoce en cualquier parte de la solicitud, pero mantenerlos al principio
evita que se interpreten como parte de la tarea).

- `--wait` (predeterminado) — en primer plano. Claude Code se bloquea en una
  sola llamada a `agy` y no muestra nada hasta que retorna; una ejecución puede
  tardar hasta 9 minutos sin mostrar progreso. Interrumpirla (Esc / Ctrl+C) no
  revierte nada: lo que `agy` ya haya editado permanece en tu árbol de trabajo;
  ejecuta `git diff` antes de hacer cualquier otra cosa.
- `--background` — Claude Code envía el subagente en segundo plano y sigue
  trabajando; la salida se te reenvía cuando termina la ejecución. Úsalo para
  cualquier cosa que pueda tardar más de un minuto.
- `--model <slug>` / `--effort low|medium|high` — consulta «Dos pools de
  cuota» más abajo.

Cada ejecución está limitada a 9 minutos (`--print-timeout 9m`). Al alcanzar
el límite, `agy` termina con código 0 y devuelve la salida disponible junto con
una línea `[agy] print timeout` (conservada desde stderr y añadida al
resultado); las ediciones hechas hasta entonces ya están en tu árbol de
trabajo. Por tanto, el código 0 no significa que la tarea haya terminado: lee
la salida y `git diff`. Dimensiona las tareas para que quepan: un archivo de
especificación, una corrección de build, un diagnóstico.

**Reanudar.** `--continue` no es un flag de `/antigravity:rescue`; el
subagente lo añade por su cuenta cuando tu solicitud continúa claramente un
trabajo anterior de Antigravity en este repositorio (expresiones como
«continúa», «sigue», «reanuda», por ejemplo
`/antigravity:rescue continue the previous task: <one-line recap of what was left>`).
`agy --continue` reanuda la conversación más reciente del workspace activo, por
lo que también puede retomar una sesión interactiva de `agy` que hayas ejecutado
en el mismo repositorio; si desde entonces has usado `agy`, vuelve a describir
la tarea completa. Nunca se añade durante el cambio automático de pool.

### Delegación proactiva

La descripción del agente `antigravity-rescue` indica a Claude Code que lo use
por su cuenta cuando tu delegado principal de razonamiento se quede sin cuota
u ocupado, cuando una segunda opinión acotada merezca una ejecución o para
trabajo mecánico en Flash cuando tu carril mecánico esté agotado; así, una vez
instalado el plugin, puede activarse en cualquier sesión de Claude Code sin que
escribas el comando. Esa ejecución envía el texto de la tarea a los modelos de
Google y les permite leer y editar archivos del repositorio actual con las
ediciones aprobadas automáticamente (la lista de denegación sigue aplicándose).
Lo que separa eso de tu árbol de trabajo es el propio sistema de permisos de
Claude Code: la única herramienta del subagente es `Bash`, así que en el modo
de permisos predeterminado (y `acceptEdits`) apruebas el comando que lanza `agy`
antes de que se ejecute, salvo que lo hayas añadido a la lista de permitidos o
hayas respondido «no volver a preguntar»; en modo bypass /
`--dangerously-skip-permissions` se ejecuta sin preguntar. No existe un
interruptor obligatorio que limite al agente a `/antigravity:rescue` (el
comando envía al mismo subagente), así que si quieres delegar solo cuando lo
pidas: omite el fragmento de CLAUDE.md de abajo, mantén activado el aviso de
Bash y añade esta línea a tu `~/.claude/CLAUDE.md`; es una instrucción que Claude
Code sigue, no una regla de permisos:

```
Never launch antigravity:antigravity-rescue on your own; use it only when I invoke /antigravity:rescue explicitly.
```

Para convertir la delegación proactiva en algo habitual, pega el bloque de
[docs/claude-md-snippet.md](docs/claude-md-snippet.md) en tu `CLAUDE.md`.
La división multicarril, el patrón en paralelo, los límites de WIP y la cadena
de fallback por cuota se encuentran en
[docs/delegation-guide.md](docs/delegation-guide.md).

### Dos pools de cuota

Antigravity mide los **modelos Gemini** en una cuota semanal y los **modelos Claude + GPT-OSS**
en una cuota separada (Antigravity app → Settings → Models & Usage muestra
ambos indicadores; con solo el CLI instalado, `agy -p "/usage"` los imprime;
consulta más abajo). El subagente los trata como dos carriles dentro del mismo
CLI:

| Clase de tarea | Pool Gemini | Pool Claude/GPT |
|---|---|---|
| mecánica (specs, renombres, boilerplate) | `gemini-3.8-flash-low` / `-medium` | `gpt-oss-120b-medium` |
| diagnóstico, corrección del build, refactorización | `gemini-3.1-pro-high` | `claude-sonnet-4-6` |
| segunda opinión, razonamiento más complejo | `gemini-3.1-pro-high` | `claude-opus-4-6-thinking` |
| no se pasa nada | valor predeterminado configurado en agy — `agy -p "/model"` lo imprime; `/model <name>` lo cambia en una sesión interactiva | — |

Antes de cada ejecución, el subagente consulta ambos indicadores con un
`agy -p "/usage"` gratuito (sin turno del agente ni gasto de cuota) y elige el
pool: si el pool del modelo solicitado está al 2 % o menos y el otro tiene
capacidad, ejecuta la tarea en el equivalente del otro pool y comienza la salida
con `[antigravity-rescue] <pool> pool at NN%, running on <slug> instead`; si
ambos pools están agotados, no ejecuta nada y devuelve
`[antigravity-rescue] both Antigravity pools exhausted (...)` con los tiempos de
reinicio. Esto importa porque un pool agotado no falla rápidamente: agy reintenta
con backoff (`RESOURCE_EXHAUSTED (code 429)` en `cli.log`) hasta el tiempo de
espera de impresión y después informa `status: ERROR` / `The stream was
interrupted`: se pierden nueve minutos por intento y la salida no contiene la
palabra cuota. Si esa firma aparece de todos modos durante la ejecución, el
subagente vuelve a consultar `/usage` y reintenta una vez en el otro pool cuando
tenga capacidad. Pasa `--model claude-sonnet-4-6` (o indica que el pool Gemini
está bajo) para comenzar directamente en el segundo pool.

### Consultar cuota y modelo desde el CLI

El modo de impresión responde por sí mismo a los comandos slash de solo lectura:
sin turno del agente, sin gasto de cuota y sin dejar una conversación
(`agy ≥ 1.1.11`):

```bash
agy -p "/usage"                        # one line per pool: name, "Weekly Limit Remaining", % left, reset time (/quota is an alias)
agy -p "/usage" --output-format json   # same data under command.data.groups[].buckets[].remaining_fraction / reset_time
agy -p "/model"                        # the default slug used when no --model is passed
agy -p "/help"                         # every command print mode answers this way
agy models                             # valid slugs (plain text only)
```

`/credits` es otro indicador — créditos adquiribles y un enlace de actualización
—, no los dos pools semanales.

Dos trampas: (1) **no** añadas `--disable-slash-commands` a estas llamadas; con
él, el texto llega al modelo, que responde como si el comando se hubiera
ejecutado, y ese turno gasta cuota; por eso el reenviador ejecuta el preflight
sin el flag y la tarea con él. (2) En Git Bash — que es lo que usa la herramienta
Bash de Claude Code en Windows — la conversión de rutas de MSYS reescribe el
argumento `/usage` como `C:/Program Files/Git/usage` antes de que agy lo vea, y
eso también se convierte en un turno del agente que gasta cuota. Antepon
`MSYS_NO_PATHCONV=1` a la llamada o ejecútala desde PowerShell/cmd.

El modelo usado por una delegación: el slug que pasaste con `--model`; de lo
contrario, lo que imprime `agy -p "/model"` (o el cambio de pool anunciado en
la primera línea de la salida). Ni el texto ni el resultado JSON de una
ejecución contienen un campo de modelo por ejecución.

`--effort low|medium|high` solo aplica a los slugs de Gemini; los slugs de Claude y GPT-OSS
llevan el esfuerzo en el nombre y agy rechaza el flag para ellos.
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
| `command(regex:.*\bgit\s+reset\b.*)` / `git\s+clean` | descartar trabajo mediante `reset`/`clean` (`checkout --`, `restore` y `stash` no están denegados; consulta más abajo) |
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
  delegues tareas que procesen contenido no confiable. Añadir `read_url(*)` /
  `mcp(*)` a `permissions.deny` bloquea únicamente las herramientas web y MCP
  integradas de agy; los comandos de shell como `curl`, `wget`,
  `Invoke-WebRequest`, `npm install` o `pip install` siguen aprobándose
  automáticamente, por lo que el delegado nunca queda completamente sin
  conexión a menos que también los deniegues (lo que rompe los builds que los
  necesitan).
- Las denegaciones por patrón son del tipo best-effort, como cualquier lista de
  permisos/denegación en CLI: un comando escrito de forma inusual podría
  filtrarse.
- El párrafo de restricciones del prompt (`Do not commit, push, switch
  branches or delete files`) es una solicitud al modelo, no una regla. De ellas,
  solo `push` y la familia `rm` están realmente denegados: `git commit`,
  `git checkout`, `git switch`, `git restore`, `git stash` y `git rebase` no lo
  están, así que un delegado que ignore el prompt puede hacer commit o descartar
  tus cambios sin commit. Haz commit o stash de tu propio trabajo antes de
  delegar y revisa `git log` y `git stash list`, además de `git diff`. Para
  imponerlo, añade
  `command(regex:.*\bgit\s+(commit|checkout|switch|restore|stash|rebase)\b.*)`
  a `permissions.deny`: es global, por lo que también bloquea esos comandos en
  tus sesiones interactivas de `agy`.
- `--add-dir "$PWD"` registra el repositorio como workspace para las propias
  herramientas de archivos de agy; no es un sandbox. Los comandos de shell se
  ejecutan como tu usuario del sistema, con tu entorno, y pueden acceder a
  cualquier ruta del disco (`~/.ssh`, `.env`, almacenes de credenciales). El
  delegado edita tu árbol de trabajo activo, no una copia: no edites los mismos
  archivos mientras haya una ejecución `--background` en curso. Para repositorios
  que contengan secretos o tareas que procesen entradas no confiables, ejecuta
  el delegado con otro usuario del sistema o en un contenedor.

## Comportamientos conocidos de agy que este plugin mitiga

| Comportamiento (agy 1.1.28) | Manejo |
|---|---|
| Las ejecuciones headless no confían en el directorio actual; las lecturas sufren soft-deny | `--add-dir "$PWD"` en cada llamada |
| Una acción denegada suavemente produce un stdout vacío y un aviso en stderr | las líneas de stderr que comienzan con `jetski:` / `[agy]` se agregan al resultado |
| Una tarea que comienza con `/` se expande como un slash command | `--disable-slash-commands` |
| `--print-timeout` devuelve una salida parcial con exit 0 | fijado en 9m, por debajo del límite de la herramienta Bash, para que un turno largo se degrade en lugar de ser cancelado |
| El instalador puede dejar `agy` fuera del PATH (visto en Windows: binario en `%LOCALAPPDATA%\agy\bin` y `~/.gemini/bin`, ninguno en el PATH) | el subagente y setup resuelven esos directorios por sí mismos; setup ofrece `agy install` |
| Un pool agotado no falla rápidamente: agy reintenta con backoff hasta el tiempo de espera de impresión y después informa `status: ERROR` / `The stream was interrupted` sin mencionar la cuota | el reenviador consulta ambos indicadores con `agy -p "/usage"` (gratuito) antes de cada ejecución y elige el pool; si ambos están agotados, devuelve el resultado inmediatamente sin ejecutar |
| `agy -p "/usage"` en Git Bash se convierte en un turno de modelo de pago (MSYS reescribe `/usage` como una ruta de Windows) | `MSYS_NO_PATHCONV=1` en cada comando slash en modo de impresión |
| `--effort` es rechazado para los slugs de Claude y GPT-OSS | el flag solo se reenvía con slugs de Gemini |

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
