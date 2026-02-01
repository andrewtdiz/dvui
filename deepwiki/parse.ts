import { mkdir, readFile, writeFile } from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";

type PagePlan = {
    id: string;
    title: string;
};

type PageEntry = {
    page_plan: PagePlan;
    content: string;
};

const invalidChars = /[<>:"/\\|?*\u0000-\u001F]/g;

const toFileName = (value: string) => value.replace(invalidChars, "-").replace(/\s+/g, "-").trim();

type PageNode = {
    id: string;
    title: string;
    fileName: string;
    children: PageNode[];
};

const splitId = (value: string) => value.split(".").map((part) => Number(part));

const compareIds = (left: string, right: string) => {
    const leftParts = splitId(left);
    const rightParts = splitId(right);
    const max = Math.max(leftParts.length, rightParts.length);
    for (let i = 0; i < max; i += 1) {
        const leftValue = leftParts[i] ?? 0;
        const rightValue = rightParts[i] ?? 0;
        if (leftValue !== rightValue) {
            return leftValue - rightValue;
        }
    }
    return 0;
};

const sortTree = (nodes: PageNode[]) => {
    nodes.sort((left, right) => compareIds(left.id, right.id));
    nodes.forEach((node) => sortTree(node.children));
};

const renderTree = (nodes: PageNode[], depth: number): string[] => {
    const lines: string[] = [];
    nodes.forEach((node) => {
        const indent = "  ".repeat(depth);
        lines.push(`${indent}- ${node.id} ${node.title}`);
        lines.push(...renderTree(node.children, depth + 1));
    });
    return lines;
};

const main = async () => {
    const filePath = fileURLToPath(import.meta.url);
    const dir = path.dirname(filePath);
    const pagesPath = path.join(dir, "pages.json");
    const pagesDir = path.join(dir, "pages");
    const raw = await readFile(pagesPath, "utf8");
    const pages = JSON.parse(raw) as PageEntry[];

    await mkdir(pagesDir, { recursive: true });

    const nodesById = new Map<string, PageNode>();
    const rootNodes: PageNode[] = [];

    await Promise.all(
        pages.map(async (page) => {
            const id = page.page_plan?.id ?? "";
            const title = page.page_plan?.title ?? "";
            const name = toFileName(`${id} ${title}`.trim());
            if (!name) {
                return;
            }
            const outPath = path.join(pagesDir, `${name}.md`);
            const body = page.content ?? "";
            await writeFile(outPath, body, "utf8");

            const node: PageNode = { id, title, fileName: name, children: [] };
            nodesById.set(id, node);
        })
    );

    nodesById.forEach((node) => {
        if (!node.id) {
            return;
        }
        const parts = node.id.split(".");
        if (parts.length === 1) {
            rootNodes.push(node);
            return;
        }
        const parentId = parts.slice(0, -1).join(".");
        const parent = nodesById.get(parentId);
        if (parent) {
            parent.children.push(node);
        } else {
            rootNodes.push(node);
        }
    });

    sortTree(rootNodes);
    const treeLines = renderTree(rootNodes, 0);
    const pagesIndex = ["# Pages", "", ...treeLines, ""].join("\n");
    const pagesIndexPath = path.join(dir, "PAGES.md");
    await writeFile(pagesIndexPath, pagesIndex, "utf8");
};

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
