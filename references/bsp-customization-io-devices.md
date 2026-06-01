# BSP customization — I/O devices

Scope: BSP-side customization for carrier-board I/O — camera plugin
manager and sensor DT, PCIe / USB3 lane wiring via `ODMDATA`,
Ethernet PHY, GPIO and pinmux, 40-pin header overlays, fan PWM,
INA3221 current monitoring, and related peripherals.

Related skills (existing coverage):

- `jetson-customize-uphy` — UPHY lane allocation (`ODMDATA`)
- `jetson-customize-pcie` — per-controller PCIe wiring
- `jetson-customize-usb` — USB2 / USB3 SS port enable/disable
- `jetson-customize-mgbe` — Multi-Gigabit Ethernet
- `jetson-customize-camera` — CSI / MIPI / GMSL sensor bring-up
- `jetson-customize-pinmux` — per-pin SFIO / direction / state

Remaining surfaces (40-pin header overlays, INA3221, fan PWM beyond
nvfancontrol) still require manual BSP edits per
`bsp-customization-software-layers.md`.
