You are running the /r-example-extra command. This is a test fixture.

RDF_TEST_MARKER_r_example_extra

Exists so the rewrite engine has a name that prefix-collides with
r-example — longest-first ordering must rewrite /r-example-extra
atomically, never as /rdf:r-example + "-extra".
