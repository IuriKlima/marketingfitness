import tseslint from 'typescript-eslint';
export default tseslint.config({ignores:['**/dist/**','**/database.types.ts']}, ...tseslint.configs.recommended);
