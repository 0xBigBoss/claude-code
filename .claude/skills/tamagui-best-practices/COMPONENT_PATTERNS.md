# Tamagui Component Patterns

Quick reference for Sheet, Dialog, Select, and Popover - components Claude is less certain about.

## Sheet (Bottom Sheet)

```tsx
import { Sheet } from 'tamagui'

function BottomSheet() {
  const [open, setOpen] = useState(false)
  const [position, setPosition] = useState(0)

  return (
    <>
      <Button onPress={() => setOpen(true)}>Open Sheet</Button>

      <Sheet
        modal
        open={open}
        onOpenChange={setOpen}
        snapPoints={[85, 50, 25]}
        position={position}
        onPositionChange={setPosition}
        dismissOnSnapToBottom
      >
        <Sheet.Overlay />
        <Sheet.Frame padding="$4">
          <Sheet.Handle />
          <YStack gap="$4">
            <Text>Sheet content here</Text>
            <Button onPress={() => setOpen(false)}>Close</Button>
          </YStack>
        </Sheet.Frame>
      </Sheet>
    </>
  )
}
```

### Key Props

| Prop | Type | Description |
|------|------|-------------|
| `modal` | boolean | Renders in portal, adds overlay behavior |
| `snapPoints` | number[] | Snap positions as % of screen height |
| `position` | number | Index into snapPoints array |
| `dismissOnSnapToBottom` | boolean | Close when dragged to bottom |
| `dismissOnOverlayPress` | boolean | Close on overlay tap |
| `zIndex` | number | Stack order |

### Native Sheet

Use native iOS/Android sheets:
```tsx
<Sheet native>
  {/* ... */}
</Sheet>
```

## Dialog

```tsx
import { Dialog, Adapt } from 'tamagui'

function ConfirmDialog() {
  return (
    <Dialog modal>
      <Dialog.Trigger asChild>
        <Button>Open Dialog</Button>
      </Dialog.Trigger>

      <Adapt when="sm" platform="touch">
        <Sheet zIndex={200000} modal dismissOnSnapToBottom>
          <Sheet.Frame padding="$4">
            <Adapt.Contents />
          </Sheet.Frame>
          <Sheet.Overlay />
        </Sheet>
      </Adapt>

      <Dialog.Portal>
        <Dialog.Overlay
          key="overlay"
          animation="quick"
          opacity={0.5}
          enterStyle={{ opacity: 0 }}
          exitStyle={{ opacity: 0 }}
        />

        <Dialog.Content
          bordered
          elevate
          key="content"
          animation={['quick', { opacity: { overshootClamping: true } }]}
          enterStyle={{ x: 0, y: -20, opacity: 0, scale: 0.9 }}
          exitStyle={{ x: 0, y: 10, opacity: 0, scale: 0.95 }}
          gap="$4"
        >
          <Dialog.Title>Confirm Action</Dialog.Title>
          <Dialog.Description>
            Are you sure you want to proceed?
          </Dialog.Description>

          <XStack gap="$3" justifyContent="flex-end">
            <Dialog.Close asChild>
              <Button>Cancel</Button>
            </Dialog.Close>
            <Button theme="active">Confirm</Button>
          </XStack>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog>
  )
}
```

### Adapt Pattern

`Adapt` transforms Dialog to Sheet on small screens/touch devices:
```tsx
<Adapt when="sm" platform="touch">
  <Sheet>
    <Sheet.Frame>
      <Adapt.Contents />  {/* Dialog content renders here */}
    </Sheet.Frame>
  </Sheet>
</Adapt>
```

## Select

```tsx
import { Check, ChevronDown, ChevronUp } from '@tamagui/lucide-icons'
import { Select, Adapt, Sheet } from 'tamagui'

function SelectDemo() {
  const [val, setVal] = useState('apple')

  return (
    <Select value={val} onValueChange={setVal}>
      <Select.Trigger width={220} iconAfter={ChevronDown}>
        <Select.Value placeholder="Select a fruit" />
      </Select.Trigger>

      <Adapt when="sm" platform="touch">
        <Sheet modal dismissOnSnapToBottom>
          <Sheet.Frame>
            <Sheet.ScrollView>
              <Adapt.Contents />
            </Sheet.ScrollView>
          </Sheet.Frame>
          <Sheet.Overlay />
        </Sheet>
      </Adapt>

      <Select.Content zIndex={200000}>
        <Select.ScrollUpButton>
          <ChevronUp size={20} />
        </Select.ScrollUpButton>

        <Select.Viewport minWidth={200}>
          <Select.Group>
            <Select.Label>Fruits</Select.Label>
            {items.map((item, i) => (
              <Select.Item key={item.name} index={i} value={item.name}>
                <Select.ItemText>{item.name}</Select.ItemText>
                <Select.ItemIndicator marginLeft="auto">
                  <Check size={16} />
                </Select.ItemIndicator>
              </Select.Item>
            ))}
          </Select.Group>
        </Select.Viewport>

        <Select.ScrollDownButton>
          <ChevronDown size={20} />
        </Select.ScrollDownButton>
      </Select.Content>
    </Select>
  )
}
```

### Native Select

Use native pickers on mobile:
```tsx
<Select native>
  {/* ... */}
</Select>
```

## Popover

```tsx
import { Popover, Adapt } from 'tamagui'

function PopoverDemo() {
  return (
    <Popover size="$5" allowFlip>
      <Popover.Trigger asChild>
        <Button>Show Info</Button>
      </Popover.Trigger>

      <Adapt when="sm" platform="touch">
        <Popover.Sheet modal dismissOnSnapToBottom>
          <Popover.Sheet.Frame padding="$4">
            <Adapt.Contents />
          </Popover.Sheet.Frame>
          <Popover.Sheet.Overlay />
        </Popover.Sheet>
      </Adapt>

      <Popover.Content
        borderWidth={1}
        borderColor="$borderColor"
        enterStyle={{ y: -10, opacity: 0 }}
        exitStyle={{ y: -10, opacity: 0 }}
        elevate
        animation={['quick', { opacity: { overshootClamping: true } }]}
      >
        <Popover.Arrow borderWidth={1} borderColor="$borderColor" />
        <YStack gap="$3">
          <Text>Popover content</Text>
          <Popover.Close asChild>
            <Button size="$2">Close</Button>
          </Popover.Close>
        </YStack>
      </Popover.Content>
    </Popover>
  )
}
```

### Positioning

| Prop | Values |
|------|--------|
| `placement` | `'top'`, `'bottom'`, `'left'`, `'right'` + `-start`, `-end` variants |
| `allowFlip` | Auto-flip when not enough space |
| `offset` | Distance from trigger |

## Common Patterns

### Portal Provider Setup

Required for Dialog, Sheet, Popover to render correctly:

```tsx
// App.tsx or _app.tsx
import { PortalProvider } from '@tamagui/portal'

function App() {
  return (
    <PortalProvider shouldAddRootHost>
      <YourApp />
    </PortalProvider>
  )
}
```

### Animation Presets

```tsx
// Quick fade/scale
animation="quick"

// Bouncy
animation="bouncy"

// Custom with easing
animation={[
  'quick',
  {
    opacity: { overshootClamping: true },
  },
]}
```

### Enter/Exit Styles

```tsx
enterStyle={{ y: -20, opacity: 0, scale: 0.9 }}
exitStyle={{ y: 10, opacity: 0, scale: 0.95 }}
```

## Fetching Full Documentation

```bash
curl -sL "https://tamagui.dev/ui/sheet.md"
curl -sL "https://tamagui.dev/ui/dialog.md"
curl -sL "https://tamagui.dev/ui/select.md"
curl -sL "https://tamagui.dev/ui/popover.md"
curl -sL "https://tamagui.dev/ui/tooltip.md"
```
