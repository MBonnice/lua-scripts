# __FCMUserWindow

Summary of modifications:
- Setters that accept `FCString` now also accept Lua `string` and `number`.
- In getters with an `FCString` parameter, the parameter is now optional and a Lua `string` is returned.

## Functions

- [GetTitle(self, title)](#gettitle)
- [SetTitle(self, title)](#settitle)

### GetTitle

```lua
__fcmuserwindow.GetTitle(self, title)
```

**[Override]**
Returns a Lua `string` and makes passing an `FCString` optional.

| Input | Type | Description |
| ----- | ---- | ----------- |
| `self` | `__FCMUserWindow` |  |
| `title` (optional) | `FCString` |  |

| Return type | Description |
| ----------- | ----------- |
| `string` |  |

### SetTitle

```lua
__fcmuserwindow.SetTitle(self, title)
```

**[Fluid] [Override]**
Accepts Lua `string` and `number` in addition to `FCString`.

| Input | Type | Description |
| ----- | ---- | ----------- |
| `self` | `__FCMUserWindow` |  |
| `title` | `FCString\|string\|number` |  |