// 构建期样式编译：把 SCSS 交给 precss 编成两个静态 CSS 文件。
//
//   app.css        md2 的三层（vendor → theme → md2）+ 本页的布局层
//   dsh-skin.css   把 dsh-console 的设计 token 覆写到 md2 的主题变量上
//
// 分成两个文件是**有意的**：对比图里那两列 rabbita 页面共用 app.css，差别只在
// 有没有挂 dsh-skin.css。这样「md2 原生暗色」与「md2 + 自己的 SCSS」是同一套 DOM、
// 同一套布局，只有主题层不同 —— 差异全部可归因到主题覆写，不掺别的变量。
//
// md2 的样式源不在本模块里：它由 moon.work 的成员路径指到磁盘上那份检出。
// 路径与 moon.work 是同一个（README 记了这件事：改一处要改两处）。
//
// precss 是纯库（String → String，零 IO），文件读取由这里注入。
//
// 运行：MOON_CC=clang MOON_AR=ar MOON_LD=clang moon run cmd/build-styles --target native

///|
/// md2 检出的根目录（相对本模块根，与 moon.work 的成员路径一致）。
let md2_root : String = "../../../../disk/ai_workspace/rabbita-material"

///|
/// md2 三层 + 我们的 app.scss → dist/assets/app.css。
/// **顺序即层叠关系**，别乱调：vendor 最早、我们的规则最后。
let app_sources : Array[String] = [
  md2_root + "/styles/vendor.scss",
  md2_root + "/styles/theme.scss",
  md2_root + "/styles/md2.scss",
  "styles/app.scss",
]

///|
/// 主题覆写层 → dist/assets/dsh-skin.css，单独一个文件。
let skin_sources : Array[String] = ["styles/dsh-skin.scss"]

///|
async fn compile(paths : Array[String], output_path : String) -> Result[Unit, String] {
  // 先把源文件读完放进内存，再构造同步 reader 交给 compile_many ——
  // precss 的核心不碰 IO，读取函数由调用方注入。
  let sources : Map[String, String] = Map([])
  for path in paths {
    let data = try @fs.read_file(path) catch {
      _ => return Err("样式源读不到: " + path)
    }
    sources[path] = data.text()
  }
  let read = fn(path : String) -> String raise @core.CompileError {
    match sources.get(path) {
      Some(text) => text
      None =>
        raise @core.CompileError::EngineFailed(
          engine="build-styles",
          message="样式源缺失: " + path,
        )
    }
  }
  let inputs = paths.map(path => @core.Input::File(path))
  let css = try @precss.compile_many(inputs, read) catch {
    e => return Err("编译失败 " + output_path + ": " + e.to_string())
  }
  let _ = try @fs.write_file(output_path, css) catch {
    e => return Err("写不进去 " + output_path + ": " + e.to_string())
  }
  println("wrote " + output_path + " (" + css.length().to_string() + " bytes)")
  Ok(())
}

///|
/// 编译失败就 abort：构建脚本宁可炸得响，也不能静默拷一份旧产物过去。
async fn run(paths : Array[String], output_path : String) -> Unit {
  match compile(paths, output_path) {
    Ok(_) => ()
    Err(reason) => abort(reason)
  }
}

///|
async fn main {
  // dist/assets 可能已存在；@fs.mkdir 不覆盖也不接受已存在，先探一次。
  if !@fs.exists("dist/assets") {
    @fs.mkdir("dist/assets", recursive=true)
  }
  run(app_sources, "dist/assets/app.css")
  run(skin_sources, "dist/assets/dsh-skin.css")
}
