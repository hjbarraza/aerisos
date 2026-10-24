// AerisOS system menu (Vicinae extension), opened by clicking Æ in the top bar or
// SUPER+ALT+SPACE. Grouped sections with monochrome icons, live state for toggles,
// battery and GPU, and the keyboard shortcut for each action on the right.

import { Action, ActionPanel, Alert, Icon, List, closeMainWindow, confirmAlert, showHUD } from "@vicinae/api";
import { execSync, spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { useState } from "react";

const BIN = `${homedir()}/.local/bin`;
const RUN = process.env.XDG_RUNTIME_DIR ?? "/tmp";

// ---- live state ----

function sh(cmd: string): string {
  try {
    return execSync(cmd, { encoding: "utf8", timeout: 1500, stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return "";
  }
}

function read(path: string): string {
  try {
    return readFileSync(path, "utf8").trim();
  } catch {
    return "";
  }
}

type State = {
  dnd: boolean;
  nightLight: boolean;
  stayAwake: boolean;
  battery: string;
  chargeMode: "hold" | "full" | "limit";
  gpu: string;
  updates: string;
};

function readState(): State {
  const pid = read(`${RUN}/stay-awake.pid`);
  const bat = sh("ls -d /sys/class/power_supply/BAT* | head -1");
  const capacity = bat ? read(`${bat}/capacity`) : "";
  const status = bat ? read(`${bat}/status`) : "";
  const power = status === "Discharging" ? "on battery" : status === "Charging" ? "charging" : "AC";
  const holding = sh("systemctl --user is-active aeris-charge-limit.timer") === "active";
  const bhoOn = sh("razer-cli read bho").includes("is on");
  let updates = "";
  try {
    updates = JSON.parse(read("/var/lib/aeris/status.json")).security?.updates ?? "";
  } catch {}
  return {
    dnd: sh("dunstctl is-paused") === "true",
    nightLight: sh("pgrep -x hyprsunset") !== "",
    stayAwake: pid !== "" && existsSync(`/proc/${pid}`),
    battery: capacity ? `${capacity}% · ${power}` : "",
    chargeMode: holding ? "hold" : bhoOn ? "limit" : "full",
    gpu: sh("envycontrol --query"),
    updates,
  };
}

// ---- running actions ----

function launch(cmd: string) {
  spawn("bash", ["-c", cmd], { detached: true, stdio: "ignore" }).unref();
}

// Close the window first, so screenshots and pickers don't capture the menu
async function runClosed(cmd: string) {
  await closeMainWindow();
  launch(cmd);
}

// Log out / restart / shut down ask first, so a stray Enter can't power off the laptop
async function runConfirmed(title: string, cmd: string) {
  const ok = await confirmAlert({
    title: `${title}?`,
    message: "Unsaved work in open apps may be lost.",
    primaryAction: { title, style: Alert.ActionStyle.Destructive },
  });
  if (ok) await runClosed(cmd);
}

async function runWithHud(cmd: string, message: string) {
  launch(cmd);
  await showHUD(message);
}

// ---- items ----

type Entry = {
  title: string;
  icon: Icon;
  run: () => void;
  subtitle?: string;
  keys?: string;
  on?: boolean; // toggles: shows ON / OFF
  active?: boolean; // current mode: shows ACTIVE
  keywords?: string[];
};

function Item({ e }: { e: Entry }) {
  const accessories: List.Item.Accessory[] = [];
  if (e.on !== undefined) accessories.push({ tag: e.on ? "ON" : "OFF" });
  if (e.active) accessories.push({ tag: "ACTIVE" });
  if (e.keys) accessories.push({ text: e.keys });
  return (
    <List.Item
      title={e.title}
      subtitle={e.subtitle}
      icon={e.icon}
      keywords={e.keywords}
      accessories={accessories}
      actions={
        <ActionPanel>
          <Action title={e.title} icon={e.icon} onAction={e.run} />
        </ActionPanel>
      }
    />
  );
}

export default function Command() {
  const [s] = useState<State>(readState);

  const power: Entry[] = [
    { title: "Lock", icon: Icon.Lock, keys: "SUPER L", run: () => runClosed("loginctl lock-session") },
    { title: "Screen Off, Stay Awake", icon: Icon.Lock, keys: "SUPER SHIFT L", run: () => runClosed("~/.local/bin/screen-off"), keywords: ["dpms", "dark"] },
    { title: "Suspend", icon: Icon.Moon, run: () => runClosed("systemctl suspend"), keywords: ["sleep"] },
    {
      title: "Log Out",
      icon: Icon.Logout,
      keys: "SUPER M",
      run: () => runConfirmed("Log Out", "command -v hyprshutdown >/dev/null && hyprshutdown || hyprctl dispatch exit"),
    },
    { title: "Restart", icon: Icon.ArrowClockwise, run: () => runConfirmed("Restart", "systemctl reboot"), keywords: ["reboot"] },
    { title: "Shut Down", icon: Icon.Power, run: () => runConfirmed("Shut Down", "systemctl poweroff"), keywords: ["power off"] },
  ];

  const toggles: Entry[] = [
    {
      title: "Do Not Disturb",
      icon: s.dnd ? Icon.BellDisabled : Icon.Bell,
      on: s.dnd,
      keys: "SUPER CTRL N",
      run: () => runWithHud(`${BIN}/dnd toggle`, s.dnd ? "Notifications on" : "Do Not Disturb on"),
    },
    {
      title: "Night Light",
      icon: Icon.Sun,
      on: s.nightLight,
      keys: "SUPER CTRL S",
      run: () => runWithHud(`${BIN}/nightlight toggle`, s.nightLight ? "Night light off" : "Night light on"),
    },
    {
      title: "Stay Awake",
      icon: Icon.Eye,
      on: s.stayAwake,
      keys: "SUPER CTRL I",
      run: () => runWithHud(`${BIN}/stay-awake toggle`, s.stayAwake ? "Stay awake off" : "Staying awake"),
    },
    {
      title: "Top Bar",
      icon: Icon.AppWindow,
      keys: "SUPER SHIFT SPACE",
      run: () => runClosed("aeris-shell bar toggle"),
      keywords: ["bar", "quickshell", "hide", "show"],
    },
  ];

  const capture: Entry[] = [
    { title: "Screenshot: Area", icon: Icon.Crop, keys: "PRINT", run: () => runClosed(`sleep 0.2; ${BIN}/screenshot area`) },
    {
      title: "Screenshot: Area and Annotate",
      icon: Icon.Pencil,
      keys: "CTRL PRINT",
      run: () => runClosed(`sleep 0.2; ${BIN}/screenshot annotate`),
    },
    {
      title: "Screenshot: Screen",
      icon: Icon.Desktop,
      keys: "SHIFT PRINT",
      run: () => runClosed(`sleep 0.3; ${BIN}/screenshot screen`),
    },
    {
      title: "Record: Area",
      subtitle: "run again to stop",
      icon: Icon.Video,
      keys: "ALT PRINT",
      run: () => runClosed(`${BIN}/screenrecord area`),
    },
    {
      title: "Record: Screen",
      subtitle: "run again to stop",
      icon: Icon.Video,
      keys: "ALT SHIFT PRINT",
      run: () => runClosed(`${BIN}/screenrecord screen`),
    },
    {
      title: "Record: Camera",
      subtitle: "Monologue: Space records, Enter edits",
      icon: Icon.Video,
      keys: "CMD SHIFT 7",
      run: () => runClosed("monologue"),
      keywords: ["webcam", "monologue", "video"],
    },
    { title: "Colour Picker", icon: Icon.EyeDropper, keys: "SUPER CTRL C", run: () => runClosed("sleep 0.2; hyprpicker -a") },
  ];

  const settings: Entry[] = [
    { title: "Wi-Fi", icon: Icon.Wifi, keys: "SUPER CTRL W", run: () => runClosed("ghostty --class=aeris.tui-float -e nmtui") },
    { title: "Bluetooth", icon: Icon.Bluetooth, keys: "SUPER CTRL B", run: () => runClosed("ghostty --class=aeris.tui-float -e bluetui") },
    { title: "Audio", icon: Icon.SpeakerOn, keys: "SUPER CTRL A", run: () => runClosed("ghostty --class=aeris.tui-float -e wiremix") },
    {
      title: "Razer",
      subtitle: "power mode, fans, logo",
      icon: Icon.Cog,
      run: () => runClosed("razer-settings"),
      keywords: ["fan", "performance"],
    },
  ];

  const battery: Entry[] = [
    {
      title: "Hold at 90–95%",
      icon: Icon.Battery,
      active: s.chargeMode === "hold",
      run: () =>
        runWithHud(
          "systemctl --user enable --now aeris-charge-limit.timer && systemctl --user start aeris-charge-limit.service",
          "Battery: holding between 90 and 95%",
        ),
    },
    {
      title: "Charge to 100%",
      icon: Icon.BatteryCharging,
      active: s.chargeMode === "full",
      run: () =>
        runWithHud("systemctl --user disable --now aeris-charge-limit.timer; razer-cli write bho off", "Battery: charging to 100%"),
    },
    {
      title: "Limit to 80%",
      subtitle: "longest battery lifespan",
      icon: Icon.Leaf,
      active: s.chargeMode === "limit",
      run: () =>
        runWithHud("systemctl --user disable --now aeris-charge-limit.timer; razer-cli write bho on 80", "Battery: limited to 80%"),
    },
  ];

  const gpu: Entry[] = [
    {
      title: "Hybrid",
      subtitle: "Intel + NVIDIA on demand",
      icon: Icon.Layers,
      active: s.gpu === "hybrid",
      run: () => runClosed("pkexec envycontrol -s hybrid && notify-send 'GPU: hybrid' 'Restart to apply'"),
    },
    {
      title: "Integrated Only",
      subtitle: "best battery life",
      icon: Icon.ComputerChip,
      active: s.gpu === "integrated",
      run: () => runClosed("pkexec envycontrol -s integrated && notify-send 'GPU: integrated' 'Restart to apply'"),
    },
  ];

  const system: Entry[] = [
    {
      title: "Update AerisOS",
      subtitle: s.updates && s.updates !== "0" ? `${s.updates} updates available` : "system, AUR, firmware, icons",
      icon: Icon.Download,
      run: () => runClosed(`ghostty --class=aeris.tui-float -e ${BIN}/aeris-update`),
    },
    { title: "Keyboard Shortcuts", icon: Icon.Keyboard, keys: "SUPER K", run: () => runClosed(`${BIN}/keybinds`) },
    { title: "Activity Monitor", icon: Icon.Gauge, run: () => runClosed("ghostty --class=aeris.tui-float -e btop"), keywords: ["btop", "cpu"] },
  ];

  const section = (title: string, entries: Entry[], subtitle?: string) => (
    <List.Section title={title} subtitle={subtitle}>
      {entries.map((e) => (
        <Item key={e.title} e={e} />
      ))}
    </List.Section>
  );

  return (
    <List navigationTitle="AerisOS" searchBarPlaceholder="Search AerisOS…">
      {section("Power", power)}
      {section("Toggles", toggles)}
      {section("Capture", capture)}
      {section("Settings", settings)}
      {section("Battery", battery, s.battery)}
      {section("GPU", gpu, s.gpu ? `${s.gpu} · restart to switch` : undefined)}
      {section("System", system)}
    </List>
  );
}
