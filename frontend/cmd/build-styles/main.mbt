// 构建期样式编译：把 SCSS 交给 precss 编成 dist/assets/app.css。
//
// 以前这里拼三个源：md2 的三层（vendor → theme → md2，从模块外的检出读）再接我们的
// app.scss，另外再出一个 dsh-skin.css 去覆写 md2 的主题变量。md2 摘掉之后那些层都不在了 ——
// 页面上的字体、颜色、形状全部由 styles/app.scss 一份定义，产物也就只有一个文件。
//
// precss 是纯库（String → String，零 IO），文件读取由这里注入。
//
// 运行：MOON_CC=clang MOON_AR=ar MOON_LD=clang moon run cmd/build-styles --target native

///|
/// 样式源。**顺序即层叠关系**，别乱调：后面的压前面的。
/// 现在只有一份（app.scss 自己内部按 reset → token → 版式排好），
/// 留成数组是为了将来真要再加一层时不用改调用点。
let app_sources : Array[String] = ["styles/app.scss"]

///|
async fn compile(
  paths : Array[String],
  output_path : String,
) -> Result[Unit, String] {
  // 先把源文件读完放进内存，再构造同步 reader 交给 compile_many ——
  // precss 的核心不碰 IO，读取函数由调用方注入。
  let sources : Map[String, String] = Map([])
  for path in paths {
    let data = @fs.read_file(path) catch {
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
  let css = @precss.compile_many(inputs, read) catch {
    e => return Err("编译失败 " + output_path + ": " + e.to_string())
  }
  let _ = @fs.write_file(output_path, css) catch {
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
}
