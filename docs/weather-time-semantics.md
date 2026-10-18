# 天气时间语义（T-158，2026-10-18）

界面标注小时 `H` 时，瞬时变量取 `H` 整点；已确认的小时区间变量统一对应 `[H, H+1h)`。
用户选择 `H:30` 时仍取该小时，不做小时内插值，也不自动改用更近的下一整点。

| 来源 | 原始时次语义 | 展示小时 H 的读取方式 |
|---|---|---|
| Open-Meteo | 温度、持续风、风向、云量、现象编码等为整点；降水量、概率、降雪量、最大小时阵风对应前一小时 | 瞬时值取 H，四个区间变量取 H+1h |
| MET Norway | instant 为瞬时；next_1_hours 为下一小时 | 均取 H；缺 next_1_hours 不用 next_6_hours 补位 |
| meteoblue basic-1h | 降水量、风速/风向均值、降雪占比及天气图标对应前一小时；basic 概率始终为前三小时（即使 data_1h）；温度等为整点 | 单小时区间取 H+1h；概率保留 H，并明确标注 H−3h 至 H，绝不转换成单小时概率；阵风本包未提供，仍为 null |
| 和风 | 逐时降水标“当前小时”，目前未取得明确区间起止说明 | 不猜测偏移；保留 H，并在指标格明确标注区间起止未确认 |

依据：[Open-Meteo Hourly Parameter Definition](https://open-meteo.com/en/docs)、
[MET 数据模型](https://docs.api.met.no/doc/locationforecast/datamodel.html)、
[meteoblue Weather Variables](https://docs.meteoblue.com/en/meteo/variables/weather-variables)。
meteoblue 图标说明见 [Forecast data](https://docs.meteoblue.com/en/weather-apis/forecast-api/forecast-data) 与供应商技术资料；
和风文档本轮访问受限，不把未核实的区间起止编成事实。

实现边界：

- `WxPointForecast.hours` 与 `rawHourAt` 是原始记录，只供编码、适配器契约和溯源。
- `hourAt` / `displayHours` 返回展示记录，并携带每个变量的 `sourceTimesUtc`。
  出发窗口保留原始时次；其他天气页可长按区间说明查看原始时次。
- 普通缓存与离线包继续保存原始记录，不改变编码、不丢失历史包、不反复偏移。
  老包最后一小时若缺 H+1h 原始记录，气温等仍可读，降水等区间值为 null；核心指标覆盖数如实降低。
- 全天降水取展示小时 `[本地00:00, 次日00:00)`，不用调用方再猜来源是否“前一小时”。
- 降水地图额外请求一个端点（49 个原始时次用于 48 个展示小时），降水读取下一时次、云量仍取本时次。
  播放时的线性混合仅为显示过渡，停在整点读取真实来源值。
- 缺失整点、缺失变量、缺失区间端点都不以相邻记录或 0 补位。
- T-195 的本地日与 UTC 请求窗缺口是另一问题，本次没有改变离线包起始窗口。
