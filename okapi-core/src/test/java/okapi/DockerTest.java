package okapi;

import guru.nidi.ramltester.RamlDefinition;
import guru.nidi.ramltester.RamlLoaders;
import guru.nidi.ramltester.restassured3.RestAssuredClient;
import io.restassured.RestAssured;
import io.restassured.response.Response;
import io.vertx.core.AsyncResult;
import io.vertx.core.DeploymentOptions;
import io.vertx.core.Future;
import io.vertx.core.Handler;
import io.vertx.core.Vertx;
import io.vertx.core.VertxOptions;
import io.vertx.core.buffer.Buffer;
import io.vertx.core.http.HttpClient;
import io.vertx.core.http.HttpClientRequest;
import io.vertx.core.json.JsonArray;
import io.vertx.core.json.JsonObject;
import io.vertx.core.logging.Logger;
import io.vertx.ext.unit.Async;
import io.vertx.ext.unit.TestContext;
import io.vertx.ext.unit.junit.VertxUnitRunner;
import java.util.LinkedList;
import org.folio.okapi.MainVerticle;
import org.folio.okapi.common.Messages;
import org.folio.okapi.common.OkapiLogger;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

@java.lang.SuppressWarnings({"squid:S1166", "squid:S1192"})
@RunWith(VertxUnitRunner.class)
public class DockerTest {

  private final Logger logger = OkapiLogger.get();
  private Vertx vertx;
  private final int port = 9230;
  private static final String LS = System.lineSeparator();
  private final LinkedList<String> locations;
  private boolean haveDocker = false;
  private HttpClient client;
  private Messages messages = Messages.getInstance();

  public DockerTest() {
    this.locations = new LinkedList<>();
  }

  @Before
  public void setUp(TestContext context) {
    Async async = context.async();
    VertxOptions options = new VertxOptions();
    options.setBlockedThreadCheckInterval(60000); // in ms
    options.setWarningExceptionTime(60000); // in ms
    vertx = Vertx.vertx(options);
    RestAssured.port = port;
    client = vertx.createHttpClient();

    checkDocker(res2 -> {
      haveDocker = res2.succeeded();
      logger.info("haveDocker = " + haveDocker);

      DeploymentOptions opt = new DeploymentOptions()
        .setConfig(new JsonObject().put("port", Integer.toString(port)));

      vertx.deployVerticle(MainVerticle.class.getName(),
        opt, res -> async.complete());
    });
  }

  @After
  public void tearDown(TestContext context) {
    logger.info("tearDown");
    td(context, context.async());
  }

  private void td(TestContext context, Async async) {
    if (locations.isEmpty()) {
      vertx.close(x -> {
        async.complete();
      });
    } else {
      String l = locations.removeFirst();
      HttpClientRequest req = client.delete(port, "localhost", l, res -> {
        td(context, async);
      });
      req.end();
    }
  }

  private void checkDocker(Handler<AsyncResult<Void>> future) {
    final String dockerUrl = "http://localhost:4243";
    final String url = dockerUrl + "/images/json?all=1";
    HttpClientRequest req = client.getAbs(url, res -> {
      Buffer body = Buffer.buffer();
      res.handler(d -> {
        body.appendBuffer(d);
      });
      res.endHandler(d -> {
        if (res.statusCode() == 200) {
          boolean gotIt = false;
          try {
            JsonArray ar = body.toJsonArray();
            for (int i = 0; i < ar.size(); i++) {
              JsonObject ob = ar.getJsonObject(i);
              JsonArray ar1 = ob.getJsonArray("RepoTags");
              if (ar1 != null) {
                for (int j = 0; j < ar1.size(); j++) {
                  String tag = ar1.getString(j);
                  if (tag != null && tag.startsWith("okapi-test-module")) {
                    gotIt = true;
                  }
                }
              }
            }
          } catch (Exception ex) {
            logger.warn(ex);
          }
          if (gotIt) {
            future.handle(Future.succeededFuture());
          } else {
            future.handle(Future.failedFuture(messages.getMessage("11700")));
          }
        } else {
          String m = messages.getMessage("11701",
            Integer.toString(res.statusCode()), body.toString());
          logger.error(m);
          future.handle(Future.failedFuture(m));
        }
      });
    });
    req.exceptionHandler(d -> {
      future.handle(Future.failedFuture(d.getMessage()));
    });
    req.end();
  }

  @Test
  public void dockerTest1(TestContext context) {
    Async async = context.async();

    logger.info("dockerTest1");
    RestAssuredClient c;
    Response r;
    RamlDefinition api = RamlLoaders.fromFile("src/main/raml").load("okapi.raml")
      .assumingBaseUri("https://okapi.cloud");

    final String docSampleDockerModule = "{" + LS
      + "  \"id\" : \"sample-module-1\"," + LS
      + "  \"name\" : \"sample module\"," + LS
      + "  \"provides\" : [ {" + LS
      + "    \"id\" : \"sample\"," + LS
      + "    \"version\" : \"1.0.0\"," + LS
      + "    \"handlers\" : [ {" + LS
      + "      \"methods\" : [ \"GET\", \"POST\" ]," + LS
      + "      \"pathPattern\" : \"/testb\"" + LS
      + "    } ]" + LS
      + "  } ]," + LS
      + "  \"launchDescriptor\" : {" + LS
      + "    \"dockerImage\" : \"okapi-test-module\"," + LS
      + "    \"dockerPull\" : false," + LS
      + "    \"dockerCMD\" : [\"-Dfoo=bar\"]," + LS
      + "    \"dockerArgs\" : {" + LS
      + "      \"StopTimeout\" : 12," + LS
      + "      \"HostConfig\": { \"PortBindings\": { \"8080/tcp\": [{ \"HostPort\": \"%p\" }] } }" + LS
      + "    }" + LS
      + "  }" + LS
      + "}";

    c = api.createRestAssured3();
    r = c.given()
      .header("Content-Type", "application/json")
      .body(docSampleDockerModule).post("/_/proxy/modules")
      .then()
      .statusCode(201).log().ifValidationFails()
      .extract().response();
    context.assertTrue(c.getLastReport().isEmpty(),
      "raml: " + c.getLastReport().toString());
    locations.add(r.getHeader("Location"));

    final String doc1 = "{" + LS
      + "  \"srvcId\" : \"sample-module-1\"," + LS
      + "  \"nodeId\" : \"localhost\"" + LS
      + "}";

    c = api.createRestAssured3();
    if (haveDocker) {
      r = c.given().header("Content-Type", "application/json")
        .body(doc1).post("/_/discovery/modules")
        .then().statusCode(201)
        .extract().response();
      locations.add(r.getHeader("Location"));
    } else {
      c.given().header("Content-Type", "application/json")
        .body(doc1).post("/_/discovery/modules")
        .then().statusCode(400);
    }
    context.assertTrue(c.getLastReport().isEmpty(),
      "raml: " + c.getLastReport().toString());

    if (!haveDocker) {
      async.complete();
      return;
    }
    final String docUserDockerModule = "{" + LS
      + "  \"id\" : \"mod-users-1\"," + LS
      + "  \"name\" : \"users\"," + LS
      + "  \"provides\" : [ {" + LS
      + "    \"id\" : \"users\"," + LS
      + "    \"version\" : \"1.0.0\"," + LS
      + "    \"handlers\" : [ {" + LS
      + "      \"methods\" : [ \"GET\", \"POST\" ]," + LS
      + "      \"pathPattern\" : \"/test\"" + LS
      + "    } ]" + LS
      + "  } ]," + LS
      + "  \"launchDescriptor\" : {" + LS
      + "    \"dockerImage\" : \"folioci/mod-users:5.0.0-SNAPSHOT\"" + LS
      + "  }" + LS
      + "}";

    c = api.createRestAssured3();
    r = c.given()
      .header("Content-Type", "application/json")
      .body(docUserDockerModule).post("/_/proxy/modules")
      .then()
      .statusCode(201)
      .extract().response();
    context.assertTrue(c.getLastReport().isEmpty(),
      "raml: " + c.getLastReport().toString());
    locations.add(r.getHeader("Location"));

    final String doc2 = "{" + LS
      + "  \"srvcId\" : \"mod-users-1\"," + LS
      + "  \"nodeId\" : \"localhost\"" + LS
      + "}";

    c = api.createRestAssured3();
    r = c.given().header("Content-Type", "application/json")
      .body(doc2).post("/_/discovery/modules")
      .then().statusCode(201)
      .extract().response();
    context.assertTrue(c.getLastReport().isEmpty(),
      "raml: " + c.getLastReport().toString());
    locations.add(r.getHeader("Location"));
    async.complete();
  }
}
