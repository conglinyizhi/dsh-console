// 应用状态与挂载点。
//
// 两个请求在 init 里一次发出去，各自带回一段原始 JSON 文本；解析放在 update 里，
// 失败的原因（不是 JSON / ok=false / 接口不可达）原样进 model，界面直接展示。

///|
priv enum Msg {
  RuntimeText(Result[String, Error])
  InstancesText(Result[String, Error])
}

///|
/// `read_time` 与 Vue 版同一口径：读数落地那一刻的浏览器本地时刻，不是服务端 readAt。
struct Model {
  runtime : RuntimeFacts?
  runtime_error : String
  instances : Array[InstanceFact]
  instances_error : String
  read_time : String
} derive(Eq)

///|
// MoonBit 现在要求把 derive 出来的 trait 方法显式提升为普通方法，
// 否则 `m.equal(...)` 这类写法将来会失效（编译器 alert_implicit_impl_as_method）。
pub extend Model with Eq::{ not_equal, equal }

///|
fn initial_model() -> Model {
  {
    runtime: None,
    runtime_error: "",
    instances: [],
    instances_error: "",
    read_time: "—",
  }
}

///|
fn load(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.batch([
    @http.get("/api/local/runtime").expect_text(emit.map(fn(res) { RuntimeText(res) })),
    @http.get("/api/local/instances").expect_text(emit.map(fn(res) { InstancesText(res) })),
  ])
}

///|
fn describe(err : Error) -> String {
  match err {
    Failure(msg) => msg
    _ => "未知错误"
  }
}

///|
fn update(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RuntimeText(res) =>
      match res {
        Ok(text) =>
          match parse_runtime(text) {
            Ok(facts) =>
              ({ ..model, runtime: Some(facts), runtime_error: "", read_time: local_time_now() }, @cmd.none)
            Err(reason) =>
              ({ ..model, runtime: None, runtime_error: reason, read_time: local_time_now() }, @cmd.none)
          }
        Err(err) =>
          ({
            ..model,
            runtime: None,
            runtime_error: "本地只读接口不可达（" + describe(err) + "）",
            read_time: local_time_now(),
          }, @cmd.none)
      }
    InstancesText(res) =>
      match res {
        Ok(text) =>
          match parse_instances(text) {
            Ok(facts) =>
              ({ ..model, instances: facts, instances_error: "" }, @cmd.none)
            Err(reason) => ({ ..model, instances: [], instances_error: reason }, @cmd.none)
          }
        Err(err) =>
          ({
            ..model,
            instances: [],
            instances_error: "本地只读接口不可达（" + describe(err) + "）",
          }, @cmd.none)
      }
  }
}

///|
pub fn app() -> @rabbita.Val[@html.Html] {
  let (model, _emit) = @rabbita.create_state_with_init(
    init=fn(emit) { (initial_model(), load(emit)) },
    update=update,
  )
  model.view(page)
}
