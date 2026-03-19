<p align="center">
  <img src="https://img.shields.io/badge/Windows%2011-LTSC%2024H2-0078D4?style=for-the-badge&logo=windows11&logoColor=white" alt="Windows 11 LTSC 24H2" />
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 5.1+" />
  <img src="https://img.shields.io/badge/Licencia-MIT-green?style=for-the-badge" alt="License MIT" />
</p>

<h1 align="center">⚡ Optimize-LTSC24H2</h1>

<p align="center">
  <strong>Script de optimización agresiva (pero usable) para Windows 11 LTSC 24H2.</strong><br/>
  Menos procesos · Menos RAM en segundo plano · Menos telemetría · Menos carga inútil.
</p>

---

## 📑 Tabla de Contenidos

- [Descripción](#-descripción)
- [Características](#-características)
- [Requisitos](#-requisitos)
- [Instalación y Uso](#-instalación-y-uso)
- [Configuración de Toggles](#-configuración-de-toggles)
- [Módulos del Script](#-módulos-del-script)
- [Registro y Logs](#-registro-y-logs)
- [Seguridad y Restauración](#-seguridad-y-restauración)
- [Preguntas Frecuentes](#-preguntas-frecuentes)
- [Contribuir](#-contribuir)
- [Licencia](#-licencia)
- [Aviso Legal](#%EF%B8%8F-aviso-legal)

---

## 📖 Descripción

**Optimize-LTSC24H2** es un script de PowerShell diseñado específicamente para instalaciones de **Windows 11 LTSC 24H2**. Su objetivo es reducir al mínimo la huella de recursos del sistema operativo desactivando servicios innecesarios, telemetría, efectos visuales y tareas programadas que consumen recursos sin aportar valor al usuario.

El script utiliza un sistema de **toggles** (interruptores booleanos) que permite activar o desactivar cada sección de optimización de forma granular, adaptándose a las necesidades de cada usuario y hardware.

> [!IMPORTANT]
> Este script **requiere reiniciar** el equipo después de ejecutarse para que todos los cambios surtan efecto al 100%.

---

## ✨ Características

| Categoría | Qué hace |
|---|---|
| 🔒 **Privacidad y Telemetría** | Desactiva la recopilación de datos, Activity Feed, publicidad y Copilot |
| 🎨 **Efectos Visuales** | Reduce animaciones, Aero Peek y delays de menú para una interfaz rápida |
| 🎮 **Game DVR / Xbox** | Desactiva Game DVR y servicios Xbox innecesarios |
| ⚙️ **Servicios** | Deshabilita servicios como DiagTrack, MapsBroker, Fax y más |
| 📅 **Tareas Programadas** | Desactiva tareas de telemetría del CEIP, feedback y diagnósticos |
| 🖥️ **Características Opcionales** | Permite desactivar Hyper-V, WSL, Sandbox y Application Guard |
| ⚡ **Plan de Energía** | Configura el plan de alto rendimiento con throttling optimizado |
| 🧹 **Limpieza** | Elimina archivos temporales y ejecuta DISM Component Cleanup |
| 🛡️ **Punto de Restauración** | Crea un punto de restauración automáticamente antes de aplicar cambios |
| 📄 **Logging Completo** | Genera log detallado + transcript de toda la sesión |

---

## 📋 Requisitos

| Requisito | Detalle |
|---|---|
| **Sistema Operativo** | Windows 11 LTSC 24H2 |
| **PowerShell** | 5.1 o superior (incluido en el sistema) |
| **Permisos** | Ejecutar como **Administrador** |
| **Espacio en disco** | Mínimo recomendado para punto de restauración |

---

## 🚀 Instalación y Uso

### 1. Clonar el repositorio

```bash
git clone https://github.com/tu-usuario/Optimizar-LTSC-24H2.git
cd Optimizar-LTSC-24H2
```

### 2. Revisar y ajustar los toggles

Abre `Optimize-LTSC24H2.ps1` con tu editor favorito y modifica los toggles según tus necesidades (ver [Configuración de Toggles](#-configuración-de-toggles)).

### 3. Ejecutar el script

```powershell
# Opción A: Click derecho → "Ejecutar con PowerShell" (como administrador)

# Opción B: Desde una terminal de PowerShell elevada
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\Optimize-LTSC24H2.ps1
```

### 4. Reiniciar el equipo

Una vez finalizada la ejecución, **reinicia el PC** para aplicar todos los cambios.

---

## 🎛️ Configuración de Toggles

El script incluye un bloque de toggles al inicio del archivo que permiten personalizar la optimización. Cambia cada valor entre `$true` y `$false` según tu configuración de hardware y preferencias:

| Toggle | Default | Descripción |
|---|:---:|---|
| `$DisableSearchIndexing` | ✅ `$true` | Desactiva el indexado de Windows Search |
| `$DisableSysMain` | ✅ `$true` | Reduce precarga en RAM y actividad en segundo plano |
| `$DisableBluetoothServices` | ❌ `$false` | Desactiva Bluetooth — solo si **NO** usas Bluetooth |
| `$DisablePrintSpooler` | ❌ `$false` | Desactiva cola de impresión — solo si **NO** imprimes |
| `$DisableBiometricService` | ❌ `$false` | Desactiva biometría — solo si **NO** usas Windows Hello |
| `$DisableLocationServices` | ✅ `$true` | Desactiva servicios de localización |
| `$DisableErrorReporting` | ✅ `$true` | Desactiva Windows Error Reporting |
| `$DisableFaxService` | ✅ `$true` | Desactiva el servicio de Fax |
| `$DisableXboxServices` | ✅ `$true` | Desactiva servicios Xbox (Auth, GameSave, NetApi) |
| `$DisableRemoteRegistry` | ✅ `$true` | Desactiva acceso remoto al registro |
| `$DisableVisualEffects` | ✅ `$true` | Aplica modo visual ligero sin animaciones |
| `$DisableHibernation` | ❌ `$false` | Desactiva hibernación y elimina `hiberfil.sys` |
| `$SetHighPerformancePlan` | ✅ `$true` | Activa plan de energía de alto rendimiento |
| `$DisableHyperV_WSL_Sandbox` | ❌ `$false` | Desactiva Hyper-V, WSL y Sandbox — **NO** si usas Docker/VM |
| `$RunComponentCleanup` | ✅ `$true` | Ejecuta limpieza de componentes con DISM |
| `$KillOneDriveIfRunning` | ✅ `$true` | Cierra OneDrive si está en ejecución (no desinstala) |
| `$DisableEdgeBackgroundMode` | ✅ `$true` | Desactiva modo background y Startup Boost de Edge |
| `$DisableBackgroundApps` | ✅ `$true` | Desactiva apps en segundo plano globalmente |
| `$DisableWidgetsAndSuggestions` | ✅ `$true` | Desactiva widgets, sugerencias, Task View y Copilot |
| `$DisableTelemetryPolicies` | ✅ `$true` | Aplica políticas de privacidad y telemetría |
| `$DisableFeedbackTasks` | ✅ `$true` | Desactiva tareas programadas de feedback y diagnóstico |
| `$ClearTempFiles` | ✅ `$true` | Limpia directorios de archivos temporales |

---

## 🧩 Módulos del Script

El script se ejecuta de forma secuencial en los siguientes módulos:

```
1. 🛡️  Punto de Restauración    → Crea un checkpoint antes de cualquier cambio
2. 🔒  Políticas / Telemetría   → Aplica claves de registro para privacidad
3. 🎨  Visual / UX              → Reduce animaciones y efectos visuales
4. 🎮  Game DVR / Xbox          → Desactiva Game DVR y grabación de juego
5. ⚙️  Servicios                → Deshabilita/manual servicios innecesarios
6. 📅  Tareas Programadas       → Desactiva tareas de telemetría y feedback
7. 🖥️  Características          → Desactiva features opcionales (Hyper-V, WSL, etc.)
8. ⚡  Energía                  → Configura plan de alto rendimiento
9. 🧹  Procesos y Limpieza      → Cierra OneDrive, limpia temp, DISM cleanup
```

---

## 📄 Registro y Logs

Todos los cambios se registran de forma detallada para auditoría y troubleshooting:

| Archivo | Ubicación | Contenido |
|---|---|---|
| **Log del script** | `C:\LTSC-OPT\optimize-YYYYMMDD-HHmmss.log` | Registro estructurado de cada acción |
| **Transcript** | `C:\LTSC-OPT\transcript-YYYYMMDD-HHmmss.txt` | Captura completa de la sesión de PowerShell |

> [!TIP]
> Revisa los logs después de la ejecución para verificar qué cambios se aplicaron correctamente y cuáles fueron omitidos.

---

## 🛡️ Seguridad y Restauración

El script implementa múltiples medidas de seguridad:

- **Punto de restauración automático**: Se crea antes de aplicar cualquier cambio, permitiendo revertir a un estado anterior desde la configuración de Windows.
- **Error handling silencioso**: Los errores no detienen la ejecución; se registran en el log y el script continúa.
- **Servicios protegidos**: Los servicios críticos del sistema no se tocan; solo se desactivan servicios prescindibles.
- **Toggles granulares**: Cada optimización puede ser activada o desactivada individualmente.

### Cómo revertir los cambios

1. **Vía Punto de Restauración**:
   - Configuración → Sistema → Recuperación → Restaurar sistema
   - Selecciona el punto "*Antes de optimizar LTSC24H2*"

2. **Manualmente**: Cada servicio desactivado puede reactivarse con:
   ```powershell
   Set-Service -Name "NombreServicio" -StartupType Automatic
   Start-Service -Name "NombreServicio"
   ```

---

## ❓ Preguntas Frecuentes

<details>
<summary><strong>¿Funciona en Windows 11 Home/Pro/Enterprise?</strong></summary>

El script fue diseñado y probado específicamente para **Windows 11 LTSC 24H2**. Podría funcionar parcialmente en otras ediciones, pero no está garantizado y algunas claves de registro o servicios pueden no existir.
</details>

<details>
<summary><strong>¿Se desinstala algo?</strong></summary>

No. El script solo **desactiva** servicios y modifica configuraciones del registro. No desinstala ningún componente del sistema. OneDrive solo se cierra (kill del proceso), no se desinstala.
</details>

<details>
<summary><strong>¿Es seguro ejecutarlo?</strong></summary>

Sí, siempre y cuando revises los toggles antes de ejecutar. El script crea un punto de restauración automáticamente. Sin embargo, como cualquier herramienta que modifica el sistema, úsalo bajo tu propia responsabilidad.
</details>

<details>
<summary><strong>¿Puedo ejecutarlo múltiples veces?</strong></summary>

Sí. El script es idempotente: aplicar los mismos cambios varias veces no causa problemas. Cada ejecución genera su propio log y punto de restauración.
</details>

---

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Si tienes ideas para mejorar el script:

1. **Fork** del repositorio
2. Crea una rama para tu feature: `git checkout -b feature/mi-mejora`
3. Haz commit de tus cambios: `git commit -m "feat: agregar nueva optimización"`
4. Push a tu rama: `git push origin feature/mi-mejora`
5. Abre un **Pull Request**

### Guías de contribución

- Mantén el estilo de código existente
- Agrega comentarios en español
- Cada nueva optimización debe tener su toggle correspondiente
- Documenta los cambios en el README
- Prueba en Windows 11 LTSC 24H2 antes de enviar el PR

---

## 📝 Licencia

Este proyecto está bajo la licencia **MIT**. Consulta el archivo [LICENSE](LICENSE) para más detalles.

---

## ⚠️ Aviso Legal

> Este script se proporciona **"tal cual" (AS IS)**, sin garantías de ningún tipo. El autor no se hace responsable de daños directos o indirectos derivados de su uso. **Ejecuta bajo tu propia responsabilidad.** Se recomienda encarecidamente hacer una copia de seguridad completa antes de la ejecución.

---

<p align="center">
  <sub>Hecho con ❤️ para la comunidad LTSC</sub>
</p>
