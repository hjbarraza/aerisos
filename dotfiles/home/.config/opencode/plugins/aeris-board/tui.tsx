// AERIS start-screen board: readiness, situation, tasking and watchlist, centered under the prompt
// (the home.board slot is added by the AERIS fork).
// Situation and watchlist data come from the AERISOS status collector (/var/lib/aeris/status.json),
// the same cache the login and lock screens read, so this never calls the upstream APIs itself.
import { Plugin } from "@opencode/plugin/tui"
import { TextAttributes } from "@opentui/core"
import { useTerminalDimensions } from "@opentui/solid"
import { createMemo, createSignal, For, Show } from "solid-js"
import fs from "fs"
import os from "os"
import path from "path"

const STATUS_FILE = "/var/lib/aeris/status.json"
const CONFIG_FILE = path.join(os.homedir(), ".config/opencode/opencode.json")
const OLLAMA = "http://127.0.0.1:11434"
const KEY_WIDTH = 6

type OllamaModel = { name: string; size: number; size_vram: number }
type Gpu = { used: number; total: number; temp: number }

function readJson(file: string): any {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"))
  } catch {
    return undefined
  }
}

async function ollamaLoaded(): Promise<OllamaModel[] | undefined> {
  try {
    const res = await fetch(`${OLLAMA}/api/ps`, { signal: AbortSignal.timeout(2000) })
    return ((await res.json()).models ?? []) as OllamaModel[]
  } catch {
    return undefined
  }
}

async function readGpu(): Promise<Gpu | undefined> {
  try {
    const proc = Bun.spawn(
      ["nvidia-smi", "--query-gpu=memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"],
      { stdout: "pipe", stderr: "ignore" },
    )
    const [used, total, temp] = (await new Response(proc.stdout).text()).trim().split(",").map((v) => Number(v.trim()))
    if ([used, total, temp].some((v) => Number.isNaN(v))) return undefined
    return { used, total, temp }
  } catch {
    return undefined
  }
}

const sameModel = (loaded: string, id: string) => loaded === id || loaded === `${id}:latest`
const gb = (bytes: number) => `${(bytes / 1e9).toFixed(1)}G`

function age(ms: number) {
  const min = Math.max(0, Math.round((Date.now() - ms) / 60000))
  if (min < 60) return `${min}M`
  if (min < 1440) return `${Math.round(min / 60)}H`
  return `${Math.round(min / 1440)}D`
}

export default Plugin.define({
  id: "aeris.board",
  setup(context) {
    const [status, setStatus] = createSignal<any>(readJson(STATUS_FILE))
    const [loaded, setLoaded] = createSignal<OllamaModel[] | undefined>()
    const [gpu, setGpu] = createSignal<Gpu | undefined>()
    const [search, setSearch] = createSignal<string | undefined>()
    const [watch, setWatch] = createSignal<any[]>([])
    const preloaded = new Set<string>()

    const selected = createMemo(() => {
      const model = context.ui.model.current()
      return model?.providerID === "ollama" ? model.modelID : undefined
    })

    // Load the selected local model as soon as AERIS opens, not on the first message
    const preload = (id: string | undefined) => {
      if (!id || preloaded.has(id)) return
      preloaded.add(id)
      fetch(`${OLLAMA}/api/generate`, {
        method: "POST",
        body: JSON.stringify({ model: id, keep_alive: "30m" }),
      }).catch(() => preloaded.delete(id))
    }

    const poll = async () => {
      setLoaded(await ollamaLoaded())
      setGpu(await readGpu())
      preload(selected())
    }
    const slow = () => {
      const s = readJson(STATUS_FILE)
      setStatus(s)
      setWatch(s?.watch?.items ?? [])
      const ws = readJson(CONFIG_FILE)?.websearch
      setSearch(ws === false ? "OFF" : (ws?.provider ?? "ASK"))
    }
    poll()
    slow()
    const fast = setInterval(poll, 5000)
    const timer = setInterval(slow, 60000)

    const sessions = createMemo(() =>
      context.data.session
        .list()
        .filter((s) => !s.parentID && !s.time.archived)
        .sort((a, b) => b.time.updated - a.time.updated)
        .slice(0, 3),
    )

    const resumeIDs = [1, 2, 3].map((n) => `aeris.resume.${n}`)
    const unbind = context.keymap.layer(() => ({
      mode: "global",
      bindings: resumeIDs,
      commands: [1, 2, 3].map((n) => ({
        id: resumeIDs[n - 1],
        title: `Resume tasking ${n}`,
        group: "AERIS",
        bind: `alt+${n}`,
        enabled: () => (context.ui.router.current() as any)?.type === "home",
        run() {
          const session = sessions()[n - 1]
          if (session) context.ui.router.navigate({ type: "session", sessionID: session.id })
        },
      })),
    }))

    const theme = () => context.theme
    const Head = (props: { children: string; right?: string }) => (
      <box flexDirection="row" justifyContent="space-between">
        <text fg={theme().text.base} attributes={TextAttributes.BOLD}>
          {`// ${props.children}`}
        </text>
        <Show when={props.right}>
          <text fg={theme().text.muted}>{props.right}</text>
        </Show>
      </box>
    )
    const Row = (props: { k: string; v: string; alert?: boolean }) => (
      <box flexDirection="row" gap={1}>
        <text fg={theme().text.muted} wrapMode="none" flexShrink={0}>
          {props.k.padStart(KEY_WIDTH)}
        </text>
        <text
          fg={props.alert ? theme().background.base : theme().text.base}
          bg={props.alert ? theme().text.base : undefined}
          wrapMode="none"
          truncate
        >
          {props.v}
        </text>
      </box>
    )

    const modelRow = createMemo(() => {
      const id = selected()
      if (!id) {
        const model = context.ui.model.current()
        return { v: model ? `CLOUD · ${model.providerID.toUpperCase()}` : "NONE SELECTED", alert: false }
      }
      const list = loaded()
      if (!list) return { v: "OLLAMA DOWN", alert: true }
      const hit = list.find((m) => sameModel(m.name, id))
      if (!hit) return { v: "LOADING…", alert: false }
      const ram = hit.size - hit.size_vram
      const split = ram > 1e8 ? `${gb(hit.size_vram)} GPU + ${gb(ram)} RAM` : `${gb(hit.size_vram)} GPU`
      return { v: `READY · ${split}`, alert: false }
    })

    const mcp = createMemo(() => {
      const list = context.data.location.mcp.server.list(context.location) ?? []
      if (!list.length) return "NONE"
      const up = list.filter((s) => s.status.status === "connected").length
      return `${up} / ${list.length} ONLINE`
    })

    const Board = () => {
      const dims = useTerminalDimensions()
      const wide = createMemo(() => dims().width >= 100)
      const s = () => status()
      const alerts = () => (s()?.alerts ?? []) as any[]

      const Left = () => (
        <box flexDirection="column" flexShrink={0} width={wide() ? 46 : "100%"} gap={1}>
          <box flexDirection="column">
            <Head>READINESS</Head>
            <Row k="MODEL" v={modelRow().v} alert={modelRow().alert} />
            <Row
              k="GPU"
              v={gpu() ? `${(gpu()!.used / 1024).toFixed(1)} / ${(gpu()!.total / 1024).toFixed(0)} GB · ${gpu()!.temp}°C` : "N/A"}
            />
            <Row k="SEARCH" v={(search() ?? "ASK").toUpperCase()} />
            <Row k="MCP" v={mcp()} />
          </box>
          <Show when={s()}>
            <box flexDirection="column">
              <Head right={s()?.updated}>SITUATION</Head>
              <Row k="AIR" v={`${s()?.air?.traffic ?? "N/A"} · ${s()?.air?.mil ?? 0} MIL`} />
              <Row k="GNSS" v={s()?.air?.gnss ?? "N/A"} />
              <Row k="SPACE" v={`KP ${s()?.space?.kp ?? "N/A"} · ${s()?.space?.scales ?? ""}`} />
              <Row k="NET" v={s()?.world?.outages ? `OUTAGES ${s()!.world.outages}` : "N/A"} />
            </box>
          </Show>
        </box>
      )

      const Right = () => (
        <box flexDirection="column" flexGrow={1} minWidth={0} gap={1}>
          <box flexDirection="column">
            <Head>TASKING</Head>
            <Show when={sessions().length} fallback={<text fg={theme().text.muted}>{"  NO OPEN TASKING"}</text>}>
              <For each={sessions()}>
                {(session, i) => (
                  <box
                    flexDirection="row"
                    justifyContent="space-between"
                    onMouseUp={() => context.ui.router.navigate({ type: "session", sessionID: session.id })}
                  >
                    <text fg={theme().text.base} wrapMode="none" truncate flexShrink={1}>
                      <span style={{ fg: theme().text.muted }}>{`ALT+${i() + 1} `}</span>
                      {(session.title ?? "UNTITLED").toUpperCase()}
                    </text>
                    <text fg={theme().text.muted} flexShrink={0}>{` ${age(session.time.updated)}`}</text>
                  </box>
                )}
              </For>
            </Show>
          </box>
          <box flexDirection="column">
            <Head right={watch().length ? `${watch().length} ITEMS` : undefined}>WATCHLIST</Head>
            <Show
              when={watch().length}
              fallback={<text fg={theme().text.muted}>{"  EMPTY · ASK AERIS TO WATCH A TOPIC"}</text>}
            >
              <For each={[...watch()].sort((a, b) => (b.new?.length ?? 0) - (a.new?.length ?? 0)).slice(0, 5)}>
                {(item: any) => (
                  <box flexDirection="row" justifyContent="space-between">
                    <text fg={theme().text.base} wrapMode="none" truncate flexShrink={1}>
                      <span style={{ fg: theme().text.muted }}>{`${item.type.toUpperCase().padEnd(6)} `}</span>
                      {item.name.toUpperCase()}
                    </text>
                    <Show
                      when={item.new?.length}
                      fallback={
                        <text fg={theme().text.muted} flexShrink={0}>{item.error ? " ERROR" : " QUIET"}</text>
                      }
                    >
                      <text fg={theme().background.base} bg={theme().text.base} flexShrink={0}>
                        {` CHANGED +${item.new.length} `}
                      </text>
                    </Show>
                  </box>
                )}
              </For>
            </Show>
          </box>
        </box>
      )

      return (
        <Show when={dims().height >= 34 && dims().width >= 60}>
          <box width={wide() ? 120 : 75} flexDirection="column" alignItems="center" flexShrink={0}>
            <For each={alerts()}>
              {(a: any) => (
                <text fg={theme().background.base} bg={theme().text.base} attributes={TextAttributes.BOLD}>
                  {` ALERT  ${typeof a === "string" ? a : (a.title ?? a.text ?? JSON.stringify(a))} `}
                </text>
              )}
            </For>
            <box width="100%" flexDirection={wide() ? "row" : "column"} gap={wide() ? 4 : 1} paddingTop={1}>
              <Left />
              <Right />
            </box>
            <box paddingTop={1}>
              <text fg={theme().text.muted}>
                {"/brief  /research  /report  /osint  /code  /watch"}
              </text>
            </box>
          </box>
        </Show>
      )
    }

    context.ui.slot({ append: "home.board", render: () => <Board /> })

    return () => {
      clearInterval(fast)
      clearInterval(timer)
      if (typeof unbind === "function") unbind()
    }
  },
})
