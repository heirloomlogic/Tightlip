// Prints the secret DemoSecrets generates, read across the module boundary, so CI can
// assert the end-to-end value.
import DemoSecrets

print(Secrets.demoKey)
