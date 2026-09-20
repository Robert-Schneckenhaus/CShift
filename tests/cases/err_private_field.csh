// Fields starting with an underscore are private to their struct.
// expect-error: field '_secret' is private
struct Vault
{
    int _secret;
    int Open;
}

int Main()
{
    var v = new Vault();
    return v._secret;
}
