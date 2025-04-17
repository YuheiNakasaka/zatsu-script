import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

export const server = new McpServer({
  name: "DiceRoller",
  version: "0.1.0",
});

server.tool(
  "getDiceRoll",
  "Roll a dice with a specified number of sides and return the result.",
  { sides: z.number().min(1).describe("Number of sides on the die") },
  async ({ sides }) => {
    const roll = Math.floor(Math.random() * sides) + 1;
    return {
      content: [
        {
          type: "text",
          text: roll.toString(),
        },
      ],
    };
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // 標準出力をするとサーバーのレスポンスとして解釈されてしまうので、標準エラー出力に出力する
  console.error("MCP Server running on stdio");
}
 
main().catch((error) => {
  console.error("Fatal error in main():", error);
  process.exit(1);
});