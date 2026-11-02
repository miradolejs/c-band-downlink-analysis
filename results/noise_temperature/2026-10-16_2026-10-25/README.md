# Temperature and noise: 16–25 October 2026

| Station | Results | Processing script |
| --- | --- | --- |
| City — Zlín | [city/](city/) | [City temperature/noise script](../../../analysis/noise_temperature/analyze_temperature_noise_city_dbsf.m) |
| Village — Hošťálkova | [village/](village/) | [Village temperature/noise script](../../../analysis/noise_temperature/analyze_temperature_noise_village_dbsf.m) |

Each station folder contains a merged MAT dataset and PNG/FIG time-series figures. One metadata temperature value is associated with all analyzed noise chunks from its source recording. Missing or invalid temperatures remain missing; the workflow does not interpolate them. The results show temporal co-variation and do not independently establish temperature as the cause of changing noise levels.
