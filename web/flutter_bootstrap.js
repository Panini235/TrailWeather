{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  // 使用随构建产物提供的渲染资源，减少首次打开对外部 CDN 的依赖。
  config: { canvasKitBaseUrl: 'canvaskit/' },
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    } catch (_) {
      window.shanqingBootFailed?.();
    }
  },
}).catch(() => window.shanqingBootFailed?.());
