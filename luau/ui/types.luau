export type Primitive = string | number | boolean

export type Reactive<T> = T | (() -> T)

export type UINode = {
  tag: string,
  key: string?,
  class: Reactive<string>?,
  scale: any?,
  visual: any?,
  transform: any?,
  scroll: any?,
  anchor: any?,
  image: any?,
  src: any?,
  listen: any?,
  children: { any }?,
  [string]: any,
}

export type EventHandler = (payload: any, id: number, kind: string) -> ()

export type NodePatch = {
  class: Reactive<string>?,
  scale: any?,
  visual: any?,
  transform: any?,
  scroll: any?,
  anchor: any?,
  image: any?,
  src: any?,
  listen: any?,
  children: { any }?,
  onClick: EventHandler?,
  onMouseEnter: EventHandler?,
  onMouseLeave: EventHandler?,
  onMouseDown: EventHandler?,
  onMouseUp: EventHandler?,
  onInput: EventHandler?,
  onFocus: EventHandler?,
  onBlur: EventHandler?,
  onEnter: EventHandler?,
}

return {}
