// @ts-nocheck
import { createSignal, Show } from "solid-js";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
  Alert,
  Badge,
  Button,
  Checkbox,
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
  DescriptionList,
  GroupBox,
  Kbd,
  List,
  Pagination,
  Progress,
  Radio,
  RadioGroup,
  Separator,
  Skeleton,
  Stepper,
  Switch,
  Toggle,
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
  Tag,
  Textarea,
} from "./components/index";

export const App = () => {
  const [lastEvent, setLastEvent] = createSignal("None");
  const [scrollDetail, setScrollDetail] = createSignal("Idle");
  const [dragDetail, setDragDetail] = createSignal("Idle");
  const [overlayOpen, setOverlayOpen] = createSignal(false);
  const [activeTab, setActiveTab] = createSignal("account");
  const [activePage, setActivePage] = createSignal(3);
  const [activeStep, setActiveStep] = createSignal(1);
  const [activeRadio, setActiveRadio] = createSignal("email");
  const [togglePressed, setTogglePressed] = createSignal(false);

  const formatPointerDetail = (detail: Record<string, unknown>) => {
    const x = detail.x;
    const y = detail.y;
    if (typeof x !== "number" || typeof y !== "number") return "";
    const button = typeof detail.button === "number" ? detail.button : 0;
    const modifiers = typeof detail.modifiers === "number" ? detail.modifiers : 0;
    return `x=${x.toFixed(1)} y=${y.toFixed(1)} btn=${button} mod=${modifiers}`;
  };

  const decodePayload = (payload?: unknown) => {
    if (payload == null) return "";
    if (typeof payload === "string") return payload;
    if (typeof payload === "object") {
      const detailValue = payload as Record<string, unknown>;
      const pointerFormatted = formatPointerDetail(detailValue);
      if (pointerFormatted) return pointerFormatted;
    }
    if (payload instanceof ArrayBuffer) {
      if (payload.byteLength === 0) return "";
      return new TextDecoder().decode(new Uint8Array(payload));
    }
    if (ArrayBuffer.isView(payload)) {
      const view = payload as ArrayBufferView;
      if (view.byteLength === 0) return "";
      return new TextDecoder().decode(
        new Uint8Array(view.buffer, view.byteOffset, view.byteLength)
      );
    }
    if (typeof payload === "object") {
      const record = payload as Record<string, unknown>;
      if (typeof record.detail === "string") return record.detail;
      if (record.detail && typeof record.detail === "object") {
        const formatted = formatPointerDetail(record.detail as Record<string, unknown>);
        if (formatted) return formatted;
        return "";
      }
      if (record.detail != null) return String(record.detail);
      if (typeof record.key === "string") return record.key;
      const target = record.target as { value?: unknown } | undefined;
      if (target?.value != null) return String(target.value);
      return "";
    }
    return String(payload);
  };

  const logEvent = (label: string) => (payload: unknown) => {
    const detail = decodePayload(payload);
    setLastEvent(detail ? `${label}: ${detail}` : label);
  };

  const logScroll = (payload: unknown) => {
    const detail = decodePayload(payload) || "Idle";
    setScrollDetail(detail);
    setLastEvent(detail === "Idle" ? "scroll" : `scroll: ${detail}`);
  };

  const logDrag = (label: string) => (payload: unknown) => {
    const detail = decodePayload(payload);
    const message = detail ? `${label}: ${detail}` : label;
    setDragDetail(message);
    setLastEvent(message);
  };

  const listItemHeight = 32;
  const listViewportHeight = 160;
  const scrollItems = Array.from({ length: 60 }, (_, index) => `Row ${index + 1}`);
  const stepItems = [
    { title: "Profile", description: "Basics" },
    { title: "Plan", description: "Billing" },
    { title: "Confirm", description: "Review" },
  ];

  return (
    <div class="flex flex-col gap-6 p-6">
      <div class="flex flex-col gap-1">
        <h1 class="text-lg text-foreground">Component Harness</h1>
        <p class="text-sm text-muted-foreground">
          Validate overlays, focus/keyboard routing, drag, and scroll behaviors.
        </p>
      </div>

      <div class="flex flex-row gap-6">
        <div class="flex flex-col gap-6">
          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <div class="flex flex-col gap-1">
              <h2 class="text-sm text-foreground">Focus + Keyboard</h2>
              <p class="text-xs text-muted-foreground">Last event: {lastEvent()}</p>
            </div>
            <div focusTrap={true} class="flex flex-col gap-3 rounded-md border border-border p-3">
              <p class="text-xs text-muted-foreground">Focus trap region</p>
              <input
                class="h-10 rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground"
                placeholder="Focusable input"
                onFocus={logEvent("focus")}
                onBlur={logEvent("blur")}
                onKeyDown={logEvent("keydown")}
                onKeyUp={logEvent("keyup")}
              />
              <div class="flex flex-row gap-2">
                <Button size="sm" onClick={logEvent("click")}>Primary</Button>
                <Button size="sm" variant="outline" onClick={logEvent("click")}>Outline</Button>
              </div>
            </div>
            <div roving={true} class="flex flex-row gap-2 rounded-md border border-border p-2">
              <Button size="sm" tabIndex={0} onFocus={logEvent("roving focus")}>One</Button>
              <Button size="sm" tabIndex={0} onFocus={logEvent("roving focus")}>Two</Button>
              <Button size="sm" tabIndex={0} onFocus={logEvent("roving focus")}>Three</Button>
            </div>
          </div>

          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <div class="flex flex-col gap-1">
              <h2 class="text-sm text-foreground">Drag + Drop</h2>
              <p class="text-xs text-muted-foreground">{dragDetail()}</p>
            </div>
            <div class="flex flex-row gap-4">
              <div
                class="flex flex-col gap-2 rounded-md border border-border p-3 w-44"
                onDragStart={logDrag("dragstart")}
                onDrag={logDrag("drag")}
                onDragEnd={logDrag("dragend")}
              >
                <p class="text-xs text-muted-foreground">Drag source</p>
                <div class="flex h-10 items-center justify-center rounded-md bg-primary text-primary-foreground">
                  Drag me
                </div>
              </div>
              <div
                class="flex flex-col gap-2 rounded-md border border-border p-3 w-44"
                onDragEnter={logDrag("dragenter")}
                onDragLeave={logDrag("dragleave")}
                onDrop={logDrag("drop")}
              >
                <p class="text-xs text-muted-foreground">Drop target</p>
                <div class="flex h-10 items-center justify-center rounded-md bg-muted text-muted-foreground">
                  Drop here
                </div>
              </div>
            </div>
          </div>

          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <h2 class="text-sm text-foreground">Inputs + Toggles</h2>
            <div class="flex flex-col gap-3">
              <Checkbox label="Receive updates" />
              <RadioGroup value={activeRadio()} onChange={setActiveRadio}>
                <Radio value="email" label="Email alerts" />
                <Radio value="sms" label="SMS alerts" />
              </RadioGroup>
              <div class="flex flex-row items-center gap-3">
                <Switch />
                <p class="text-sm text-muted-foreground">Enable preview</p>
              </div>
              <div class="flex flex-row items-center gap-3">
                <Toggle pressed={togglePressed()} onChange={setTogglePressed}>
                  Auto-save
                </Toggle>
                <p class="text-xs text-muted-foreground">{togglePressed() ? "On" : "Off"}</p>
              </div>
              <Textarea placeholder="Type notes..." rows={3} />
            </div>
          </div>

          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <div class="flex flex-col gap-1">
              <h2 class="text-sm text-foreground">Tabs</h2>
              <p class="text-xs text-muted-foreground">Active tab: {activeTab()}</p>
            </div>
            <Tabs value={activeTab()} onChange={setActiveTab} class="flex flex-col gap-3">
              <TabsList>
                <TabsTrigger value="account">Account</TabsTrigger>
                <TabsTrigger value="billing">Billing</TabsTrigger>
                <TabsTrigger value="team">Team</TabsTrigger>
              </TabsList>
              <TabsContent value="account">
                <p class="text-sm text-muted-foreground">Manage profile and password.</p>
              </TabsContent>
              <TabsContent value="billing">
                <p class="text-sm text-muted-foreground">Update payment details.</p>
              </TabsContent>
              <TabsContent value="team">
                <p class="text-sm text-muted-foreground">Invite collaborators.</p>
              </TabsContent>
            </Tabs>
          </div>

          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <h2 class="text-sm text-foreground">Actions + Containers</h2>
            <GroupBox title="Team Access" description="Manage roles and visibility.">
              <div class="flex flex-row gap-2">
                <Button size="sm">Invite</Button>
                <Button size="sm" variant="secondary">Settings</Button>
              </div>
            </GroupBox>
            <Accordion type="single" defaultValue="overview" collapsible={true}>
              <AccordionItem value="overview">
                <AccordionTrigger>Overview</AccordionTrigger>
                <AccordionContent>Quick status and usage details.</AccordionContent>
              </AccordionItem>
              <AccordionItem value="details">
                <AccordionTrigger>Details</AccordionTrigger>
                <AccordionContent>Additional configuration and metadata.</AccordionContent>
              </AccordionItem>
            </Accordion>
            <Collapsible defaultOpen={true}>
              <CollapsibleTrigger class="rounded-md bg-muted px-2 py-1">Notes</CollapsibleTrigger>
              <CollapsibleContent>
                Use collapsible panels for optional helper copy.
              </CollapsibleContent>
            </Collapsible>
          </div>
        </div>

        <div class="flex flex-col gap-6">
          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <div class="flex flex-col gap-1">
              <h2 class="text-sm text-foreground">Scroll Region</h2>
              <p class="text-xs text-muted-foreground">{scrollDetail()}</p>
            </div>
            <List
              class="h-40 w-full rounded-md border border-border scrollbar-thumb-border"
              items={scrollItems}
              itemSize={listItemHeight}
              viewportHeight={listViewportHeight}
              virtual={true}
              itemClass="flex h-8 items-center rounded-md border border-border px-2 text-sm text-foreground"
              onScroll={logScroll}
            />
          </div>

          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <h2 class="text-sm text-foreground">Overlay Staging</h2>
            <p class="text-xs text-muted-foreground">
              Open the modal to validate portal layering and focus trapping.
            </p>
            <Button size="sm" onClick={() => setOverlayOpen(true)}>Open overlay</Button>
          </div>

          <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96">
            <h2 class="text-sm text-foreground">Status + Feedback</h2>
            <div class="flex flex-row gap-2">
              <Badge>Beta</Badge>
              <Badge variant="secondary">Stable</Badge>
              <Badge variant="outline">Outline</Badge>
            </div>
            <div class="flex flex-row gap-2">
              <Tag>Internal</Tag>
              <Tag class="bg-secondary text-secondary-foreground">Release</Tag>
            </div>
            <div class="flex flex-row items-center gap-1">
              <p class="text-xs text-muted-foreground">Shortcut</p>
              <Kbd>⌘</Kbd>
              <Kbd>K</Kbd>
            </div>
            <Alert title="Snapshot note">Validate new styling before shipping.</Alert>
            <DescriptionList
              items={[
                { term: "Status", description: "Operational" },
                { term: "Region", description: "us-east-1" },
              ]}
            />
            <Separator />
            <Progress value={42} />
            <div class="flex flex-row gap-2">
              <Skeleton class="h-4 w-24" />
              <Skeleton class="h-4 w-16" />
              <Skeleton class="h-4 w-12" />
            </div>
            <Stepper
              steps={stepItems}
              value={activeStep()}
              onChange={setActiveStep}
            />
            <Pagination page={activePage()} totalPages={8} onChange={setActivePage} />
          </div>
        </div>
      </div>

      <Show when={overlayOpen()}>
        <portal modal={true} focusTrap={true}>
          <div class="flex h-full w-full items-center justify-center">
            <div class="flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-80">
              <h3 class="text-sm text-foreground">Overlay Preview</h3>
              <p class="text-xs text-muted-foreground">
                Press buttons and use Tab to ensure focus stays inside.
              </p>
              <div class="flex flex-row gap-2">
                <Button size="sm" onClick={() => setOverlayOpen(false)}>Close</Button>
                <Button size="sm" variant="secondary">Action</Button>
              </div>
            </div>
          </div>
        </portal>
      </Show>
    </div>
  );
};
