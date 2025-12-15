---
name: tamagui-best-practices
description: Provides Tamagui patterns for config v4, compiler optimization, styled context, and cross-platform styling. Must use when working with Tamagui projects (tamagui.config.ts, @tamagui imports).
---

This skill provides patterns for Tamagui v1.x that go beyond fundamentals. It focuses on Config v4, compiler optimization, compound components, and common mistakes.

## Config v4 Quick Start

Use `@tamagui/config/v4` for simplified setup:

```tsx
// tamagui.config.ts
import { defaultConfig } from '@tamagui/config/v4'
import { createTamagui } from 'tamagui'

export const config = createTamagui(defaultConfig)

type CustomConfig = typeof config

declare module 'tamagui' {
  interface TamaguiCustomConfig extends CustomConfig {}
}
```

**Recommended setting** for new projects (aligns flexBasis to React Native):
```tsx
export const config = createTamagui({
  ...defaultConfig,
  settings: {
    ...defaultConfig.settings,
    styleCompat: 'react-native',
  },
})
```

### createThemes Pattern

For custom themes, use `createThemes` with palette/accent/childrenThemes:

```tsx
import { createThemes, defaultComponentThemes } from '@tamagui/config/v4'

const generatedThemes = createThemes({
  componentThemes: defaultComponentThemes,
  base: {
    palette: {
      dark: ['#050505', '#151515', /* ...12 colors */ '#fff'],
      light: ['#fff', '#f8f8f8', /* ...12 colors */ '#000'],
    },
    extra: {
      light: { ...Colors.blue, shadowColor: 'rgba(0,0,0,0.04)' },
      dark: { ...Colors.blueDark, shadowColor: 'rgba(0,0,0,0.2)' },
    },
  },
  accent: {
    palette: { dark: lightPalette, light: darkPalette }, // inverted
  },
  childrenThemes: {
    blue: { palette: { dark: Object.values(Colors.blueDark), light: Object.values(Colors.blue) } },
    red: { /* ... */ },
    green: { /* ... */ },
  },
})
```

## Token and Theme Syntax

### $ Prefix Rules

- **Props**: Use `$` prefix for token references: `<Text color="$color" fontSize="$4" />`
- **Theme keys**: Access without `$` in theme definitions: `{ color: palette[11] }`
- **Token access in variants**: Use `tokens.size[name]` pattern

### Variant Spread Operators

Special spread operators map token categories to variant values:

```tsx
const Button = styled(View, {
  variants: {
    size: {
      // Maps size tokens: $1, $2, $true, etc.
      '...size': (size, { tokens }) => ({
        height: tokens.size[size] ?? size,
        borderRadius: tokens.radius[size] ?? size,
        gap: tokens.space[size]?.val * 0.2,
      }),
    },
    textSize: {
      // Maps fontSize tokens
      '...fontSize': (name, { font }) => ({
        fontSize: font?.size[name],
      }),
    },
  } as const,
})
```

**Important**: Use `as const` on variants object until TypeScript supports inferred const generics.

## Compound Components with createStyledContext

For compound APIs like `<Button><Button.Text>Click</Button.Text></Button>`:

```tsx
import {
  SizeTokens,
  View,
  Text,
  createStyledContext,
  styled,
  withStaticProperties,
} from '@tamagui/core'

// 1. Create context with shared variant types
export const ButtonContext = createStyledContext<{ size: SizeTokens }>({
  size: '$medium',
})

// 2. Create frame with context
export const ButtonFrame = styled(View, {
  name: 'Button',
  context: ButtonContext,
  variants: {
    size: {
      '...size': (name, { tokens }) => ({
        height: tokens.size[name],
        borderRadius: tokens.radius[name],
        gap: tokens.space[name].val * 0.2,
      }),
    },
  } as const,
  defaultVariants: {
    size: '$medium',
  },
})

// 3. Create text with same context (variants auto-sync)
export const ButtonText = styled(Text, {
  name: 'ButtonText',
  context: ButtonContext,
  variants: {
    size: {
      '...fontSize': (name, { font }) => ({
        fontSize: font?.size[name],
      }),
    },
  } as const,
})

// 4. Compose with withStaticProperties
export const Button = withStaticProperties(ButtonFrame, {
  Props: ButtonContext.Provider,
  Text: ButtonText,
})
```

**Usage**:
```tsx
<Button size="$large">
  <Button.Text>Click me</Button.Text>
</Button>

// Or override defaults from above:
<Button.Props size="$small">
  <Button><Button.Text>Small</Button.Text></Button>
</Button.Props>
```

**Note**: `context` pattern does not work with compiler flattening. Use for higher-level components (Button, Card), not primitives (Stack, Text).

## styleable() for Wrapper Components

When wrapping a styled component in a functional component, use `.styleable()` to preserve variant inheritance:

```tsx
const StyledText = styled(Text)

// WITHOUT styleable - BROKEN variant inheritance
const BrokenWrapper = (props) => <StyledText {...props} />

// WITH styleable - CORRECT
const CorrectWrapper = StyledText.styleable((props, ref) => (
  <StyledText ref={ref} {...props} />
))

// Now this works:
const StyledCorrectWrapper = styled(CorrectWrapper, {
  variants: {
    bold: { true: { fontWeight: 'bold' } },
  },
})
```

### Adding Extra Props

Pass generic type argument for additional props:

```tsx
type ExtraProps = { icon?: React.ReactNode }

const IconText = StyledText.styleable<ExtraProps>((props, ref) => {
  const { icon, ...rest } = props
  return (
    <XStack>
      {icon}
      <StyledText ref={ref} {...rest} />
    </XStack>
  )
})
```

## accept Prop for Custom Components

Enable token/theme resolution on non-standard props:

```tsx
// For SVG fill/stroke that should accept theme colors
const StyledSVG = styled(SVG, {}, {
  accept: { fill: 'color', stroke: 'color' } as const,
})

// Usage: <StyledSVG fill="$blue10" />

// For style objects (like ScrollView's contentContainerStyle)
const MyScrollView = styled(ScrollView, {}, {
  accept: { contentContainerStyle: 'style' } as const,
})

// Usage: <MyScrollView contentContainerStyle={{ padding: '$4' }} />
```

**Important**: Use `as const` on the accept object.

## Prop Order Matters

In `styled()`, prop order determines override priority:

```tsx
// backgroundColor can be overridden by props
const Overridable = (props) => (
  <View backgroundColor="$red10" {...props} width={200} />
)
// width CANNOT be overridden (comes after spread)

// Variant order matters too:
<Component scale={3} huge />  // scale = 3 (scale comes first)
<Component huge scale={3} />  // scale = 2 (huge overrides)
```

## Anti-Patterns

### Dynamic Styles Break Optimization

```tsx
// BAD - breaks compiler optimization
<View style={{ width: someVariable * 2 }} />
<View backgroundColor={isDark ? '$gray1' : '$gray12'} />

// GOOD - use variants
const Box = styled(View, {
  variants: {
    dark: { true: { backgroundColor: '$gray1' }, false: { backgroundColor: '$gray12' } },
  },
})
<Box dark={isDark} />
```

### Inline Functions

```tsx
// BAD - new function every render
<View onPress={() => handlePress(id)} />

// GOOD - stable reference
const handlePressCallback = useCallback(() => handlePress(id), [id])
<View onPress={handlePressCallback} />
```

### Wrong Import Paths

```tsx
// These are different packages with different contents:
import { View } from 'tamagui'           // Full UI kit
import { View } from '@tamagui/core'     // Core only (smaller)
import { Button } from '@tamagui/button' // Individual component

// Pick one approach and be consistent
```

### Mixing RN StyleSheet with Tamagui

```tsx
// BAD - StyleSheet values don't resolve tokens
const styles = StyleSheet.create({ box: { padding: 20 } })
<View style={styles.box} backgroundColor="$blue10" />

// GOOD - all Tamagui
<View padding="$4" backgroundColor="$blue10" />
```

## Fetching Current Documentation

For latest API details, fetch markdown docs directly:

```bash
# Core docs
curl -sL "https://tamagui.dev/docs/core/configuration.md"
curl -sL "https://tamagui.dev/docs/core/styled.md"
curl -sL "https://tamagui.dev/docs/core/variants.md"
curl -sL "https://tamagui.dev/docs/core/animations.md"

# Component docs
curl -sL "https://tamagui.dev/ui/sheet.md"
curl -sL "https://tamagui.dev/ui/dialog.md"
curl -sL "https://tamagui.dev/ui/select.md"

# Full docs index
curl -sL "https://tamagui.dev/llms.txt"
```

For HTML pages, use the web-fetch skill with appropriate selectors.

## Quick Reference

### Config v4 Shorthands (Tailwind-aligned)

| Shorthand | Property |
|-----------|----------|
| `bg` | backgroundColor |
| `p` | padding |
| `m` | margin |
| `w` | width |
| `h` | height |
| `br` | borderRadius |

### Media Query Breakpoints

| Token | Default | Server Default |
|-------|---------|----------------|
| `$xs` | 660px | true |
| `$sm` | 800px | false |
| `$md` | 1020px | false |
| `$lg` | 1280px | false |
| `$xl` | 1420px | false |

### Animation Drivers

| Driver | Platform | Use Case |
|--------|----------|----------|
| `css` | Web | Default, best performance |
| `react-native-reanimated` | Native | Required for native animations |

## Progressive Disclosure

For compiler optimization details, see @COMPILER_PATTERNS.md
For Sheet/Dialog/Select patterns, see @COMPONENT_PATTERNS.md
For design system thinking, see @DESIGN_SYSTEM.md
