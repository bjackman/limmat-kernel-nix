{ pkgs }:
{
    config = {
        tests = [
            {
                name = "hello";
                command = "echo hello world";
            }
        ];
    };
}