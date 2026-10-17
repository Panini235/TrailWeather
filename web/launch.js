(() => {
  const launch = document.getElementById('launch');
  const status = document.getElementById('launch-status');
  const retry = document.getElementById('launch-retry');
  let slowLoad;
  let failed = false;
  window.shanqingBootFailed = () => {
    if (!launch.isConnected) return;
    failed = true;
    clearTimeout(slowLoad);
    status.textContent = '暂时无法打开。请检查网络连接后重试。已保存的数据不会因重新加载而清除。';
    retry.hidden = false;
  };
  retry.addEventListener('click', () => window.location.reload());
  window.addEventListener('flutter-first-frame', () => {
    clearTimeout(slowLoad);
    launch.remove();
    delete window.shanqingBootFailed;
  }, { once: true });
  // 捕获启动脚本本身无法下载的情况；应用运行后的业务请求不进入此路径。
  window.addEventListener('error', (event) => {
    if (event.target?.id === 'flutter-bootstrap') window.shanqingBootFailed?.();
  }, true);
  slowLoad = setTimeout(() => {
    if (failed || !launch.isConnected) return;
    status.textContent = '首次打开可能需要一些时间。若一直无法进入，请检查网络连接后重新加载。';
    retry.hidden = false;
  }, 20000);
})();
